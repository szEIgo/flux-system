#!/usr/bin/env bash
# DESCRIPTION: rotate
# USAGE: make rotate-keys
# CATEGORY: maintenance
# DETAILS: sops

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source configuration
source "$SCRIPT_DIR/config.sh"

SECRETS_DIR="$REPO_ROOT/$SECRETS_DIR"
GITHUB_TOKEN_FILE="$REPO_ROOT/.secrets/github-pat.sops.yaml"

echo "Rotating age key and re-encrypting secrets..."

# Generate new key
mkdir -p "$(dirname "$AGE_KEY")"
age-keygen -o "$AGE_KEY.new"

# Update .sops.yaml
NEWPUB=$(age-keygen -y "$AGE_KEY.new")
if command -v yq >/dev/null 2>&1; then
    yq -i '.creation_rules[0].age = strenv(NEWPUB)' "$REPO_ROOT/.sops.yaml"
else
    sed -i "s|^\s*-\s*age:.*|- age: $NEWPUB|" "$REPO_ROOT/.sops.yaml"
fi

# Re-encrypt secrets
echo "Re-encrypting $SECRETS_DIR/*.enc.yaml (if any)"
for file in "$SECRETS_DIR"/*.enc.yaml; do
    [ -f "$file" ] || continue
    sops -d "$file" > /tmp/secret.tmp
    SOPS_AGE_KEY_FILE="$AGE_KEY.new" sops -e /tmp/secret.tmp > "$file"
    rm -f /tmp/secret.tmp
    echo "  ✓ Re-encrypted $(basename "$file")"
done

# Re-encrypt GitHub token
echo "Re-encrypting $GITHUB_TOKEN_FILE (if present)"
if [ -f "$GITHUB_TOKEN_FILE" ]; then
    SOPS_AGE_KEY_FILE="$AGE_KEY" sops -d "$GITHUB_TOKEN_FILE" > /tmp/ghtoken.tmp
    SOPS_AGE_KEY_FILE="$AGE_KEY.new" sops -e /tmp/ghtoken.tmp > "$GITHUB_TOKEN_FILE"
    rm -f /tmp/ghtoken.tmp
    echo "  ✓ Re-encrypted GitHub PAT"
fi

# Replace old key
mv "$AGE_KEY.new" "$AGE_KEY"

# Update cluster secret
echo "Updating cluster sops-age secret..."
kubectl create secret generic sops-age \
    --from-file=age.agekey="$AGE_KEY" \
    -n flux-system \
    --dry-run=client -o yaml | kubectl apply -f -

# Reconcile
echo "Reconciling..."
flux reconcile kustomization flux-system --with-source

echo "✓ Rotation complete. Commit .sops.yaml and any changed secrets."
