#!/usr/bin/env bash
# DESCRIPTION: sops-age rm
# USAGE: make clean
# CATEGORY: maintenance
# DETAILS: cluster

set -euo pipefail

echo "Removing SOPS secret..."
kubectl delete secret sops-age -n flux-system 2>/dev/null || echo "Secret not found"
echo "✓"
