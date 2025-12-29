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

# Preflight: ensure CoreDNS can resolve public hosts (e.g., github.com)
echo "Preflight: ensuring CoreDNS is installed and configured..."
# If Deployment missing, apply full CoreDNS kustomization (SA, RBAC, Service, Deployment, ConfigMap)
if ! kubectl -n kube-system get deploy coredns >/dev/null 2>&1; then
    echo "CoreDNS deployment missing; applying kustomization..."
    kubectl apply -k "$REPO_ROOT/k8s/infrastructure/coredns" || true
else
    echo "CoreDNS deployment present; patching ConfigMap..."
    kubectl apply -f "$REPO_ROOT/k8s/infrastructure/coredns/coredns-configmap.yaml" || true
    kubectl -n kube-system rollout restart deployment coredns || true
fi

# Wait for CoreDNS deployment to be Ready
echo "Waiting for CoreDNS to be Ready..."
kubectl -n kube-system rollout status deploy/coredns --timeout=120s || true

# Ensure kube-dns Service has the expected clusterIP (k3s default: 10.43.0.10)
EXPECTED_DNS_IP="10.43.0.10"
ACTUAL_DNS_IP=$(kubectl -n kube-system get svc kube-dns -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
if [ -n "$ACTUAL_DNS_IP" ] && [ "$ACTUAL_DNS_IP" != "$EXPECTED_DNS_IP" ]; then
    echo "kube-dns clusterIP ($ACTUAL_DNS_IP) != expected ($EXPECTED_DNS_IP); recreating Service..."
    kubectl -n kube-system delete svc kube-dns || true
    kubectl apply -f "$REPO_ROOT/k8s/infrastructure/coredns/coredns-service.yaml" || true
fi

# DNS health checks: internal service and external host
echo "Preflight: checking cluster DNS (svc + external) via busybox..."
DNS_OK=0
for i in $(seq 1 6); do
    # Try resolving an internal service and github.com from a short-lived pod
    kubectl run dns-check-$RANDOM --rm -i --restart=Never --image=busybox:1.36 \
        -- nslookup kubernetes.default.svc.cluster.local >/tmp/dns_internal.$$ 2>&1 || true
    kubectl run dns-check-$RANDOM --rm -i --restart=Never --image=busybox:1.36 \
        -- nslookup github.com >/tmp/dns_external.$$ 2>&1 || true
    if grep -qi 'address' /tmp/dns_internal.$$ && grep -qi 'address' /tmp/dns_external.$$; then
        DNS_OK=1
        echo "DNS resolution OK"
        break
    fi
    echo "Attempt $i: DNS not yet healthy; retrying in 5s..."
    sleep 5
done
rm -f /tmp/dns_internal.$$ /tmp/dns_external.$$ || true

if [ "$DNS_OK" -ne 1 ]; then
    echo "ERROR: Cluster DNS unhealthy. CoreDNS may be missing or misconfigured."
    echo "- Check kube-dns service endpoints: kubectl -n kube-system get endpoints kube-dns"
    echo "- Ensure CoreDNS pods exist: kubectl -n kube-system get pods | grep -i coredns"
    echo "- If missing, re-enable the k3s CoreDNS addon or reinstall CoreDNS"
    exit 1
fi

# Try to use encrypted GitHub token
TOKEN=""
if [ -f "$GITHUB_TOKEN_FILE" ]; then
    TOKEN=$(SOPS_AGE_KEY_FILE="$AGE_KEY" sops -d --extract '["github_token"]' "$GITHUB_TOKEN_FILE" 2>/dev/null || true)
fi

# If no token and not interactive, fail fast with guidance
if [ -z "$TOKEN" ] && [ ! -t 0 ]; then
    echo "ERROR: No GitHub token available and no interactive TTY to prompt."
    echo "- Add an encrypted PAT: make add-gh-pat (requires SOPS/age key)"
    echo "- Or set env GITHUB_TOKEN and re-run make up"
    exit 1
fi

echo "Running Flux bootstrap..."
BOOTSTRAP_LOG=$(mktemp)
BOOTSTRAP_STATUS=0

# Bootstrap command with shorter timeout to fail faster if there are issues
if [ -n "$TOKEN" ]; then
    echo "Using encrypted GitHub token from $GITHUB_TOKEN_FILE"
    if ! timeout 180 bash -c "GITHUB_TOKEN='$TOKEN' flux bootstrap github \
        --owner='$GITHUB_OWNER' \
        --repository='$GITHUB_REPO' \
        --branch='$GITHUB_BRANCH' \
        --path='$FLUX_PATH' \
        --personal \
        --token-auth" | tee "$BOOTSTRAP_LOG"; then
        BOOTSTRAP_STATUS=$?
    fi
else
    echo "No encrypted token found; will prompt interactively"
    if ! timeout 180 bash -c "flux bootstrap github \
        --owner='$GITHUB_OWNER' \
        --repository='$GITHUB_REPO' \
        --branch='$GITHUB_BRANCH' \
        --path='$FLUX_PATH' \
        --personal" | tee "$BOOTSTRAP_LOG"; then
        BOOTSTRAP_STATUS=$?
    fi
fi

# If bootstrap timed out or failed with GitRepository not found, manually apply manifests
if [ "$BOOTSTRAP_STATUS" -ne 0 ]; then
    if grep -q "not found" "$BOOTSTRAP_LOG" 2>/dev/null; then
        echo ""
        echo "WARN: Bootstrap waiting failed (resources not found immediately)."
        echo "This is often normal - flux bootstrap creates resources but doesn't wait."
        echo "Continuing with manual verification..."
    else
        echo "ERROR: Flux bootstrap failed (exit $BOOTSTRAP_STATUS)."
        echo "Bootstrap output:" && tail -50 "$BOOTSTRAP_LOG" || true
        echo ""
        echo "Troubleshooting tips:"
        echo "- Verify PAT decryption: SOPS_AGE_KEY_FILE=$AGE_KEY sops -d --extract '[\"github_token\"]' $GITHUB_TOKEN_FILE"
        echo "- Confirm GitHub settings: owner=$GITHUB_OWNER repo=$GITHUB_REPO branch=$GITHUB_BRANCH path=$FLUX_PATH"
        echo "- Ensure network/DNS to api.github.com works (we already checked github.com DNS)."
        rm -f "$BOOTSTRAP_LOG" || true
        exit $BOOTSTRAP_STATUS
    fi
fi
rm -f "$BOOTSTRAP_LOG" || true

# Verify Flux CRDs exist before waiting (guards against silent bootstrap failures)
echo "Checking Flux CRDs exist..."
if ! kubectl get crd gitrepositories.source.toolkit.fluxcd.io >/dev/null 2>&1; then
    echo "ERROR: Flux CRDs missing. Bootstrap likely did not install controllers."
    echo "- Check bootstrap output above and retry after fixing token/network."
    exit 1
fi

# Apply gotk-sync.yaml to ensure GitRepository and Kustomization exist
# This is a workaround for bootstrap race conditions
echo "Ensuring sync objects exist by applying gotk-sync.yaml..."
if kubectl apply -f "$REPO_ROOT/k8s/clusters/home/flux-system/gotk-sync.yaml"; then
    echo "✓ Applied gotk-sync.yaml"
else
    echo "ERROR: Failed to apply gotk-sync.yaml"
    echo "- Check that $REPO_ROOT/k8s/clusters/home/flux-system/gotk-sync.yaml exists"
    exit 1
fi

# Verify the bootstrap sync objects exist
echo "Verifying bootstrap sync objects (GitRepository/Kustomization)..."
for i in $(seq 1 10); do
    if kubectl -n flux-system get gitrepositories.source.toolkit.fluxcd.io flux-system >/dev/null 2>&1 && \
       kubectl -n flux-system get kustomizations.kustomize.toolkit.fluxcd.io flux-system >/dev/null 2>&1; then
        echo "✓ GitRepository and Kustomization verified"
        break
    fi
    if [ "$i" -eq 10 ]; then
        echo "ERROR: Sync objects not found after applying gotk-sync.yaml"
        kubectl -n flux-system get gitrepositories,kustomizations || true
        exit 1
    fi
    echo "Waiting for sync objects... ($i/10)"
    sleep 2
done

# Verify the Git credentials secret exists (for private repos)
if ! kubectl -n flux-system get secret flux-system >/dev/null 2>&1; then
    echo "WARN: Git credentials Secret 'flux-system' not found in namespace flux-system."
    echo "- If your repo is private, source-controller will fail to fetch."
    echo "- Ensure bootstrap completed successfully or create the secret manually."
fi

# Wait for GitRepository to produce an artifact
echo "Waiting for GitRepository artifact..."
for i in $(seq 1 30); do
    if flux get source git flux-system -n flux-system 2>/dev/null | grep -q "Ready\s*True"; then
        echo "Git source Ready"
        break
    fi
    echo "Attempt $i: source not ready yet; retrying..."
    sleep 5
done

# If still not ready, exit with guidance
if ! flux get source git flux-system -n flux-system 2>/dev/null | grep -q "Ready\s*True"; then
    echo "ERROR: flux-system GitRepository source not ready. Check network/PAT and Git repo settings."
    flux get source git flux-system -n flux-system || true
    exit 1
fi

# Configure SOPS decryption
echo "Configuring SOPS decryption on flux-system Kustomization..."
kubectl patch kustomization flux-system -n flux-system \
    --type merge -p '{"spec":{"decryption":{"provider":"sops","secretRef":{"name":"sops-age"}}}}' || \
    echo "WARN: Could not patch flux-system Kustomization for SOPS (may already be configured)"

# Reconcile flux-system to trigger deployment of all resources
echo "Reconciling flux-system Kustomization..."
flux reconcile kustomization flux-system -n flux-system --with-source

# Wait for child Kustomizations to be created
echo "Waiting for child Kustomizations to be created..."
EXPECTED_KS="cert-manager cert-manager-issuers envoy-gateway envoy-gateway-proxy apps"
for ks in $EXPECTED_KS; do
    echo -n "  Waiting for $ks..."
    for i in $(seq 1 60); do
        if kubectl -n flux-system get kustomization "$ks" >/dev/null 2>&1; then
            echo " ✓"
            break
        fi
        if [ "$i" -eq 60 ]; then
            echo " TIMEOUT"
            echo "WARN: Kustomization $ks not created after 60s"
            echo "  This may be normal if the resource isn't in your repo yet"
        fi
        sleep 1
    done
done

echo ""
echo "✓ Flux bootstrap complete!"
echo ""
echo "Next steps:"
echo "  1. Check status: make status"
echo "  2. Watch reconciliation: flux get kustomizations -A --watch"
echo "  3. View logs: make logs"
