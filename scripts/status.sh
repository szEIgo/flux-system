#!/usr/bin/env bash
# DESCRIPTION: Show Flux status and infrastructure pods
# USAGE: make status
# CATEGORY: operations
# DETAILS: Displays Kustomization status and running infrastructure pods

set -euo pipefail

echo "=== Flux Status ==="
flux get kustomization -n flux-system flux-system || true
echo ""

echo "=== Infrastructure Pods ==="
kubectl get pods -n cert-manager 2>/dev/null || echo "cert-manager: not deployed"
kubectl get pods -n ingress-nginx 2>/dev/null || echo "ingress-nginx: not deployed"
