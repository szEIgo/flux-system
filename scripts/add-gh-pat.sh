#!/usr/bin/env bash
# DESCRIPTION: gh pat
# USAGE: make add-gh-pat
# CATEGORY: secrets
# DETAILS: sops file

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/config.sh"

usage() {
	echo "gh pat"
	echo "env: GITHUB_TOKEN"
	echo "opt: --stdin"
}

GITHUB_TOKEN_FILE="$REPO_ROOT/$GITHUB_TOKEN_SOPS_FILE"

mkdir -p "$(dirname "$GITHUB_TOKEN_FILE")"

TOKEN="${GITHUB_TOKEN:-}"
if [[ "${1:-}" == "--stdin" ]]; then
	TOKEN="$(cat)"
fi

if [ -z "$TOKEN" ]; then
	usage
	exit 1
fi

tmpfile="$(mktemp)"
trap 'rm -f "$tmpfile"' EXIT

printf '%s\n' "github_token: $TOKEN" > "$tmpfile"
sops -e "$tmpfile" > "$GITHUB_TOKEN_FILE"

echo "ok"
