#!/usr/bin/env bash
# DESCRIPTION: Bootstrap Flux from GitHub repository
# USAGE: make up
# CATEGORY: setup
# DETAILS: Checks for sops-age secret, uses encrypted GitHub token if available,
#          and patches Kustomization for SOPS decryption

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source configuration
source "$SCRIPT_DIR/config.sh"

GITHUB_TOKEN_FILE="$REPO_ROOT/.secrets/github-pat.sops.yaml"

echo "Bootstrapping Flux from GitHub..."

# Verify sops-age secret exists
if ! kubectl -n flux-system get secret sops-age >/dev/null 2>&1; then
    echo "ERROR: sops-age secret missing. Run 'make init' first."
    exit 1
fi

# Try to use encrypted GitHub token
TOKEN=""
if [ -f "$GITHUB_TOKEN_FILE" ]; then
    TOKEN=$(SOPS_AGE_KEY_FILE="$AGE_KEY" sops -d --extract '["github_token"]' "$GITHUB_TOKEN_FILE" 2>/dev/null || true)
fi

# Bootstrap
if [ -n "$TOKEN" ]; then
    echo "Using encrypted GitHub token from $GITHUB_TOKEN_FILE"
    GITHUB_TOKEN="$TOKEN" flux bootstrap github \
        --owner="$GITHUB_OWNER" \
        --repository="$GITHUB_REPO" \
        --branch="$GITHUB_BRANCH" \
        --path="$FLUX_PATH" \
        --personal \
        --token-auth
else
    echo "No encrypted token found; will prompt interactively"
    flux bootstrap github \
        --owner="$GITHUB_OWNER" \
        --repository="$GITHUB_REPO" \
        --branch="$GITHUB_BRANCH" \
        --path="$FLUX_PATH" \
        --personal
fi

# Configure SOPS decryption
echo "Configuring SOPS decryption on flux-system Kustomization..."
kubectl patch kustomization flux-system -n flux-system \
    --type merge -p '{"spec":{"decryption":{"provider":"sops","secretRef":{"name":"sops-age"}}}}'

# Reconcile
echo "Reconciling..."
flux reconcile kustomization flux-system --with-source

echo "✓ Flux bootstrapped with SOPS"
