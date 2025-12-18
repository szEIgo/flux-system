#!/usr/bin/env bash
# DESCRIPTION: Tail kustomize-controller logs (follow mode)
# USAGE: make logs
# CATEGORY: operations
# DETAILS: Streams kustomize-controller logs for debugging

set -euo pipefail

echo "=== Flux Logs (kustomize-controller) ==="
kubectl logs -n flux-system deployment/kustomize-controller --tail=50
