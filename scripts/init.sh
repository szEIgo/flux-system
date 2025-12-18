#!/usr/bin/env bash
# DESCRIPTION: Initialize SOPS encryption and cluster decryption
# USAGE: make init
# CATEGORY: setup
# DETAILS: Ensures age key exists, creates sops-age Secret in flux-system namespace,
#          and patches flux-system Kustomization for SOPS decryption

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source configuration
source "$SCRIPT_DIR/config.sh"

echo "=== Initializing SOPS + cluster decryption ==="

# Check/generate age key
if [ ! -f "$AGE_KEY" ]; then
    read -p "No age key at $AGE_KEY. Generate new? (y/n): " gen
    if [ "$gen" = "y" ]; then
        mkdir -p "$(dirname "$AGE_KEY")"
        age-keygen -o "$AGE_KEY"
        PUB=$(age-keygen -y "$AGE_KEY")
        echo "Updating .sops.yaml recipient to $PUB"
        if command -v yq >/dev/null 2>&1; then
            yq -i '.creation_rules[0].age = strenv(PUB)' "$REPO_ROOT/.sops.yaml"
        else
            sed -i "s|^\s*-\s*age:.*|- age: $PUB|" "$REPO_ROOT/.sops.yaml"
        fi
    else
        read -p "Path to existing age key file: " keypath
        mkdir -p "$(dirname "$AGE_KEY")"
        cp "$keypath" "$AGE_KEY"
    fi
fi

# Create flux-system namespace
echo "Creating namespace flux-system (if missing)..."
kubectl create namespace flux-system 2>/dev/null || true

# Create/update sops-age secret
echo "Creating/Updating sops-age secret..."
kubectl create secret generic sops-age \
    --from-file=age.key="$AGE_KEY" \
    -n flux-system \
    --dry-run=client -o yaml | kubectl apply -f -

# Patch flux-system Kustomization for SOPS decryption
echo "Patching flux-system Kustomization for SOPS decryption (if exists)..."
kubectl patch kustomization flux-system -n flux-system \
    --type merge -p '{"spec":{"decryption":{"provider":"sops","secretRef":{"name":"sops-age"}}}}' 2>/dev/null || true

echo "✓ Init complete"
