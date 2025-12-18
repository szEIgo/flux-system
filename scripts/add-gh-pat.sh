#!/usr/bin/env bash
# DESCRIPTION: Store encrypted GitHub Personal Access Token
# USAGE: make add-gh-pat
# CATEGORY: secrets
# DETAILS: Encrypts and stores GitHub PAT for automated bootstrap (optional)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

GITHUB_TOKEN_FILE="$REPO_ROOT/.secrets/github-pat.sops.yaml"

echo "=== Store encrypted GitHub PAT for bootstrap ==="
mkdir -p "$REPO_ROOT/.secrets"

read -sp "GitHub PAT (will be stored encrypted): " token
echo

echo "github_token: $token" > /tmp/github-pat.yaml
sops -e /tmp/github-pat.yaml > "$GITHUB_TOKEN_FILE"
rm -f /tmp/github-pat.yaml

echo "✓ Encrypted token saved to $GITHUB_TOKEN_FILE"
echo "Next: git add $GITHUB_TOKEN_FILE && git commit -m 'Add encrypted GH PAT' && git push"
