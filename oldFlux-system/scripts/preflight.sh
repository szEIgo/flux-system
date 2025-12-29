#!/usr/bin/env bash
# DESCRIPTION: Pre-flight check before running make up
# USAGE: ./scripts/preflight.sh
# CATEGORY: setup
# DETAILS: Validates prerequisites are met for a successful bootstrap

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source configuration
source "$SCRIPT_DIR/config.sh"

echo "=== Flux GitOps Pre-flight Check ==="
echo ""

ERRORS=0
WARNINGS=0

# Check 1: kubectl access
echo -n "✓ Checking kubectl access... "
if kubectl cluster-info >/dev/null 2>&1; then
    echo "OK"
else
    echo "FAIL"
    echo "  ERROR: kubectl cannot access cluster"
    echo "  Fix: Ensure kubeconfig is set up and cluster is running"
    ERRORS=$((ERRORS + 1))
fi

# Check 2: Flux CLI
echo -n "✓ Checking flux CLI... "
if command -v flux >/dev/null 2>&1; then
    FLUX_VERSION=$(flux version --client 2>/dev/null | grep 'flux:' | awk '{print $2}')
    echo "OK ($FLUX_VERSION)"
else
    echo "FAIL"
    echo "  ERROR: flux CLI not found"
    echo "  Fix: Install flux CLI from https://fluxcd.io/flux/installation/"
    ERRORS=$((ERRORS + 1))
fi

# Check 3: SOPS
echo -n "✓ Checking sops... "
if command -v sops >/dev/null 2>&1; then
    SOPS_VERSION=$(sops --version 2>&1 | head -n 1 | awk '{print $2}')
    echo "OK ($SOPS_VERSION)"
else
    echo "FAIL"
    echo "  ERROR: sops not found"
    echo "  Fix: Install sops from https://github.com/getsops/sops"
    ERRORS=$((ERRORS + 1))
fi

# Check 4: Age
echo -n "✓ Checking age... "
if command -v age >/dev/null 2>&1; then
    AGE_VERSION=$(age --version 2>&1 | head -n 1 | awk '{print $2}')
    echo "OK ($AGE_VERSION)"
else
    echo "FAIL"
    echo "  ERROR: age not found"
    echo "  Fix: Install age from https://github.com/FiloSottile/age"
    ERRORS=$((ERRORS + 1))
fi

# Check 5: Age key exists
echo -n "✓ Checking age key... "
if [ -f "$AGE_KEY" ]; then
    echo "OK"
    # Verify .sops.yaml matches
    if [ -f "$REPO_ROOT/.sops.yaml" ]; then
        AGE_PUB=$(age-keygen -y "$AGE_KEY" 2>/dev/null)
        SOPS_PUB=$(grep 'age:' "$REPO_ROOT/.sops.yaml" | awk '{print $3}' | head -n 1)
        if [ "$AGE_PUB" = "$SOPS_PUB" ]; then
            echo "  ✓ Age key matches .sops.yaml"
        else
            echo "  WARN: Age key public key doesn't match .sops.yaml"
            echo "  Current key: $AGE_PUB"
            echo "  .sops.yaml:  $SOPS_PUB"
            echo "  Fix: Run 'make init' to update .sops.yaml"
            WARNINGS=$((WARNINGS + 1))
        fi
    fi
else
    echo "FAIL"
    echo "  ERROR: Age key not found at $AGE_KEY"
    echo "  Fix: Run 'make init' to generate a key"
    ERRORS=$((ERRORS + 1))
fi

# Check 6: sops-age secret in cluster
echo -n "✓ Checking sops-age secret in cluster... "
if kubectl -n flux-system get secret sops-age >/dev/null 2>&1; then
    echo "OK"
else
    echo "WARN"
    echo "  WARN: sops-age secret not found in flux-system namespace"
    echo "  Fix: Run 'make init' to create it"
    WARNINGS=$((WARNINGS + 1))
fi

# Check 7: GitHub token
echo -n "✓ Checking GitHub token... "
GITHUB_TOKEN_FILE="$REPO_ROOT/.secrets/github-pat.sops.yaml"
if [ -f "$GITHUB_TOKEN_FILE" ]; then
    # Try to decrypt it
    if TOKEN=$(SOPS_AGE_KEY_FILE="$AGE_KEY" sops -d --extract '["github_token"]' "$GITHUB_TOKEN_FILE" 2>/dev/null); then
        if [ -n "$TOKEN" ]; then
            echo "OK (encrypted)"
        else
            echo "WARN"
            echo "  WARN: GitHub token file exists but is empty"
            WARNINGS=$((WARNINGS + 1))
        fi
    else
        echo "WARN"
        echo "  WARN: Cannot decrypt GitHub token (age key mismatch?)"
        echo "  Fix: Run 'make add-gh-pat' to re-encrypt with current key"
        WARNINGS=$((WARNINGS + 1))
    fi
elif [ -n "${GITHUB_TOKEN:-}" ]; then
    echo "OK (environment variable)"
else
    echo "WARN"
    echo "  WARN: No GitHub token found (will prompt interactively)"
    echo "  Fix: Run 'make add-gh-pat' or set GITHUB_TOKEN env var"
    WARNINGS=$((WARNINGS + 1))
fi

# Check 8: GitHub repository settings
echo -n "✓ Checking GitHub repository settings... "
echo "owner=$GITHUB_OWNER repo=$GITHUB_REPO branch=$GITHUB_BRANCH"
if [ -z "$GITHUB_OWNER" ] || [ -z "$GITHUB_REPO" ] || [ -z "$GITHUB_BRANCH" ]; then
    echo "  ERROR: GitHub settings incomplete in scripts/config.sh"
    ERRORS=$((ERRORS + 1))
fi

# Check 9: Storage class
echo -n "✓ Checking default storage class... "
if kubectl get storageclass local-path >/dev/null 2>&1; then
    echo "OK (local-path)"
elif kubectl get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}' 2>/dev/null | grep -q .; then
    DEFAULT_SC=$(kubectl get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}')
    echo "OK ($DEFAULT_SC)"
else
    echo "WARN"
    echo "  WARN: No default storage class found"
    echo "  Info: local-path is expected for k3s"
    WARNINGS=$((WARNINGS + 1))
fi

# Check 10: Required secrets for apps
echo -n "✓ Checking required app secrets... "
MISSING_SECRETS=0
if ! kubectl get namespace contact >/dev/null 2>&1; then
    echo ""
    echo "  WARN: Namespace 'contact' doesn't exist"
    echo "  Info: Will be created by Flux, but contact-service-secrets must be created manually"
    WARNINGS=$((WARNINGS + 1))
elif ! kubectl -n contact get secret contact-service-secrets >/dev/null 2>&1; then
    echo ""
    echo "  WARN: Secret 'contact-service-secrets' not found in namespace 'contact'"
    echo "  Fix: Create it before apps deploy:"
    echo "    kubectl create secret docker-registry contact-service-secrets \\"
    echo "      --docker-server=ghcr.io \\"
    echo "      --docker-username=YOUR_GITHUB_USERNAME \\"
    echo "      --docker-password=YOUR_GITHUB_PAT \\"
    echo "      --namespace=contact"
    WARNINGS=$((WARNINGS + 1))
    MISSING_SECRETS=1
else
    echo "OK"
fi

# Check 11: Test secret decryption
echo -n "✓ Testing SOPS decryption... "
if SOPS_AGE_KEY_FILE="$AGE_KEY" sops -d "$REPO_ROOT/k8s/apps/schmidtsgarage-secret.yaml" >/dev/null 2>&1; then
    echo "OK"
else
    echo "FAIL"
    echo "  ERROR: Cannot decrypt secrets with current age key"
    echo "  Fix: Ensure age key matches the one used to encrypt secrets"
    ERRORS=$((ERRORS + 1))
fi

# Summary
echo ""
echo "=== Summary ==="
if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
    echo "✓ All checks passed! Ready to run 'make up'"
    exit 0
elif [ "$ERRORS" -eq 0 ]; then
    echo "⚠ $WARNINGS warning(s) found. You can proceed but may encounter issues."
    echo "  Review warnings above and fix if possible."
    exit 0
else
    echo "✗ $ERRORS error(s) and $WARNINGS warning(s) found."
    echo "  Fix errors before running 'make up'"
    exit 1
fi
