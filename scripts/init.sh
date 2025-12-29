#!/usr/bin/env bash
# DESCRIPTION: sops init
# USAGE: make init
# CATEGORY: setup
# DETAILS: age key, sops-age

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source configuration
source "$SCRIPT_DIR/config.sh"

echo "sops init"

# age key (non-interactive)
# Optional: AGE_KEY_IMPORT=/path/to/age.key
if ! command -v age-keygen >/dev/null 2>&1; then
    echo "ERR: age-keygen"
    exit 1
fi

if [ ! -f "$AGE_KEY" ]; then
    mkdir -p "$(dirname "$AGE_KEY")"
    if [ -n "${AGE_KEY_IMPORT:-}" ]; then
        if [ ! -f "$AGE_KEY_IMPORT" ]; then
            echo "ERR: AGE_KEY_IMPORT"
            exit 1
        fi
        cp "$AGE_KEY_IMPORT" "$AGE_KEY"
    else
        age-keygen -o "$AGE_KEY"
    fi
fi

# Sync .sops.yaml recipient
PUB=$(age-keygen -y "$AGE_KEY")
SOPS_RULES_PATH="$REPO_ROOT/$SOPS_RULES_FILE"
if [ -f "$SOPS_RULES_PATH" ]; then
    if command -v yq >/dev/null 2>&1; then
        PUB="$PUB" yq -i '.creation_rules[0].age = strenv(PUB)' "$SOPS_RULES_PATH"
    else
        sed -i "s|^\s*-\s*age:.*|- age: $PUB|" "$SOPS_RULES_PATH"
    fi
else
    echo "ERR: $SOPS_RULES_FILE"
    exit 1
fi

# Namespace
kubectl create namespace "$FLUX_NAMESPACE" 2>/dev/null || true

# Create/update sops-age secret
echo "sops-age"
kubectl create secret generic sops-age \
    --from-file=age.agekey="$AGE_KEY" \
    -n "$FLUX_NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -

# Patch flux-system Kustomization for SOPS decryption
kubectl patch kustomization flux-system -n "$FLUX_NAMESPACE" \
    --type merge -p '{"spec":{"decryption":{"provider":"sops","secretRef":{"name":"sops-age"}}}}' 2>/dev/null || true

echo "ok"
