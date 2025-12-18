#!/usr/bin/env bash
# DESCRIPTION: Remove sops-age secret from cluster
# USAGE: make clean
# CATEGORY: maintenance
# DETAILS: Deletes the sops-age Secret from flux-system namespace

set -euo pipefail

echo "=== Removing SOPS secret ==="
kubectl delete secret sops-age -n flux-system 2>/dev/null || echo "Secret not found"
echo "✓"
