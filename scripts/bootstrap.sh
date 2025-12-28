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

# DNS health checks: internal service and external host
echo "Preflight: checking cluster DNS (svc + external) via busybox..."
DNS_OK=0
for i in $(seq 1 6); do
    # Try resolving an internal service and github.com from a short-lived pod
    kubectl run dns-check-$RANDOM --rm -i --restart=Never --image=busybox:1.36 \
        -- nslookup notification-controller.flux-system.svc.cluster.local >/tmp/dns_internal.$$ 2>&1 || true
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

# Bootstrap
if [ -n "$TOKEN" ]; then
        echo "Using encrypted GitHub token from $GITHUB_TOKEN_FILE"
        GITHUB_TOKEN="$TOKEN" flux bootstrap github \
                --owner="$GITHUB_OWNER" \
                --repository="$GITHUB_REPO" \
                --branch="$GITHUB_BRANCH" \
                --path="$FLUX_PATH" \
                --personal \
                --token-auth || true
else
        echo "No encrypted token found; will prompt interactively"
        flux bootstrap github \
                --owner="$GITHUB_OWNER" \
                --repository="$GITHUB_REPO" \
                --branch="$GITHUB_BRANCH" \
                --path="$FLUX_PATH" \
                --personal || true
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
    --type merge -p '{"spec":{"decryption":{"provider":"sops","secretRef":{"name":"sops-age"}}}}' || true

# Reconcile
echo "Reconciling root (flux-system) and stack..."
flux reconcile kustomization flux-system -n flux-system --with-source
# Reconcile infra first, then gateway, then proxy, then apps
flux reconcile kustomization envoy-gateway -n flux-system --with-source || true
flux reconcile kustomization envoy-gateway-proxy -n flux-system --with-source || true
flux reconcile kustomization apps -n flux-system --with-source || true

echo "✓ Flux bootstrapped and stack reconciled"
