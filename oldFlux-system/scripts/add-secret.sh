#!/usr/bin/env bash
# DESCRIPTION: Create new SOPS-encrypted Kubernetes Secret
# USAGE: make add-secret
# CATEGORY: secrets
# DETAILS: Interactively creates, encrypts, and adds secret to kustomization

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source configuration
source "$SCRIPT_DIR/config.sh"

SECRETS_DIR="$REPO_ROOT/$SECRETS_DIR"
KUSTOMIZATION_FILE="$REPO_ROOT/$KUSTOMIZATION_FILE"

echo "Adding new SOPS-encrypted Kubernetes Secret..."

read -p "Secret filename (without .enc.yaml): " name
read -p "Secret key (e.g., github-token): " key
read -sp "Secret value: " value
echo

# Create secret YAML
mkdir -p /tmp/sops-tmp
cat > /tmp/sops-tmp/$name.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: $name
  namespace: flux-system
type: Opaque
stringData:
  $key: $value
EOF

# Encrypt and save
secret_file="$name.enc.yaml"
sops -e /tmp/sops-tmp/$name.yaml > "$SECRETS_DIR/$secret_file"
rm -f /tmp/sops-tmp/$name.yaml

echo "✓ Created $SECRETS_DIR/$secret_file"

# Add to kustomization.yaml
if command -v yq >/dev/null 2>&1; then
    RES=$(yq '.resources[]? // empty' "$KUSTOMIZATION_FILE" | grep -Fx "$secret_file" || true)
    if [ -z "$RES" ]; then
        yq -i '.resources += ["'"$secret_file"'"]' "$KUSTOMIZATION_FILE"
        echo "✓ Added to kustomization: $secret_file"
    else
        echo "Already listed in kustomization: $secret_file"
    fi
else
    if grep -qE '^\s*resources:\s*\[\s*\]' "$KUSTOMIZATION_FILE"; then
        sed -i 's#^\s*resources:\s*\[\s*\]#resources:\n  - '"$secret_file"'#' "$KUSTOMIZATION_FILE"
    elif grep -qE '^\s*resources:\s*$' "$KUSTOMIZATION_FILE"; then
        echo "  - $secret_file" >> "$KUSTOMIZATION_FILE"
    elif ! grep -q '^resources:' "$KUSTOMIZATION_FILE"; then
        echo -e '\nresources:\n  - '"$secret_file" >> "$KUSTOMIZATION_FILE"
    else
        echo "  - $secret_file" >> "$KUSTOMIZATION_FILE"
    fi
    echo "✓ Added to kustomization: $secret_file"
fi

echo "Next: git add $SECRETS_DIR/$secret_file $KUSTOMIZATION_FILE && git commit -m 'Add $name secret' && git push"
