#!/usr/bin/env bash
# DESCRIPTION: secret add
# USAGE: make add-secret ARGS="--name n --key k --value v"
# CATEGORY: secrets
# DETAILS: sops enc

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source configuration
source "$SCRIPT_DIR/config.sh"

SECRETS_DIR="$REPO_ROOT/$SECRETS_DIR"
KUSTOMIZATION_FILE="$REPO_ROOT/$KUSTOMIZATION_FILE"

usage() {
    echo "secret add"
    echo "req: --name --key"
    echo "val: --value | --value-file | --stdin"
    echo "env: SECRET_NAME SECRET_KEY SECRET_VALUE SECRET_VALUE_FILE"
}

SECRET_NAMESPACE="${SECRET_NAMESPACE:-$FLUX_NAMESPACE}"
SECRET_NAME="${SECRET_NAME:-}"
SECRET_KEY="${SECRET_KEY:-}"
SECRET_VALUE="${SECRET_VALUE:-}"
SECRET_VALUE_FILE="${SECRET_VALUE_FILE:-}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name) SECRET_NAME="${2:-}"; shift 2 ;;
        --key) SECRET_KEY="${2:-}"; shift 2 ;;
        --value) SECRET_VALUE="${2:-}"; shift 2 ;;
        --value-file) SECRET_VALUE_FILE="${2:-}"; shift 2 ;;
        --stdin) SECRET_VALUE="$(cat)"; shift ;;
        --namespace) SECRET_NAMESPACE="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ERR: arg $1"; usage; exit 1 ;;
    esac
done

if [ -z "$SECRET_NAME" ] || [ -z "$SECRET_KEY" ]; then
    usage
    exit 1
fi

if [ -z "$SECRET_VALUE" ] && [ -n "$SECRET_VALUE_FILE" ]; then
    if [ ! -f "$SECRET_VALUE_FILE" ]; then
        echo "ERR: value-file"
        exit 1
    fi
    SECRET_VALUE="$(cat "$SECRET_VALUE_FILE")"
fi

if [ -z "$SECRET_VALUE" ]; then
    usage
    exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

cat > "$tmpdir/$SECRET_NAME.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
    name: $SECRET_NAME
    namespace: $SECRET_NAMESPACE
type: Opaque
stringData:
    $SECRET_KEY: $SECRET_VALUE
EOF

# Encrypt and save
secret_file="$SECRET_NAME.enc.yaml"
mkdir -p "$SECRETS_DIR"
sops -e "$tmpdir/$SECRET_NAME.yaml" > "$SECRETS_DIR/$secret_file"

echo "ok"

# kustomization
if [ ! -f "$KUSTOMIZATION_FILE" ]; then
	echo "ERR: kustomization"
	exit 1
fi

if command -v yq >/dev/null 2>&1; then
	if ! yq '.resources[]? // empty' "$KUSTOMIZATION_FILE" 2>/dev/null | grep -Fxq "$secret_file"; then
		yq -i '.resources += ["'"$secret_file"'"]' "$KUSTOMIZATION_FILE"
	fi
else
	if ! grep -Fxq "  - $secret_file" "$KUSTOMIZATION_FILE" && ! grep -Fxq "- $secret_file" "$KUSTOMIZATION_FILE"; then
		printf '%s\n' "  - $secret_file" >> "$KUSTOMIZATION_FILE"
	fi
fi
