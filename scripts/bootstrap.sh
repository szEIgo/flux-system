#!/usr/bin/env bash
# DESCRIPTION: flux bootstrap
# USAGE: make up
# CATEGORY: setup
# DETAILS: github

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source configuration
source "$SCRIPT_DIR/config.sh"

GITHUB_TOKEN_FILE="$REPO_ROOT/$GITHUB_TOKEN_SOPS_FILE"

usage() {
    echo "flux bootstrap"
    echo "req: GITHUB_TOKEN"
    echo "alt: make add-gh-pat"
}

echo "bootstrap"

# Verify sops-age secret exists
if ! kubectl -n "$FLUX_NAMESPACE" get secret sops-age >/dev/null 2>&1; then
    echo "ERR: sops-age"
    exit 1
fi

# Try to use encrypted GitHub token
TOKEN=""
if [ -f "$GITHUB_TOKEN_FILE" ]; then
    TOKEN=$(SOPS_AGE_KEY_FILE="$AGE_KEY" sops -d --extract '["github_token"]' "$GITHUB_TOKEN_FILE" 2>/dev/null || true)
fi

if [ -z "$TOKEN" ] && [ -n "${GITHUB_TOKEN:-}" ]; then
    TOKEN="$GITHUB_TOKEN"
fi

if [ -z "$TOKEN" ]; then
    usage
    exit 1
fi

GITHUB_TOKEN="$TOKEN" flux bootstrap github \
	--owner="$GITHUB_OWNER" \
	--repository="$GITHUB_REPO" \
	--branch="$GITHUB_BRANCH" \
	--path="$FLUX_PATH" \
	--personal \
	--token-auth

# Configure SOPS decryption
echo "decrypt"
kubectl patch kustomization flux-system -n "$FLUX_NAMESPACE" \
    --type merge -p '{"spec":{"decryption":{"provider":"sops","secretRef":{"name":"sops-age"}}}}'

# Reconcile
echo "reconcile"
flux reconcile kustomization flux-system --with-source

echo "ok"
