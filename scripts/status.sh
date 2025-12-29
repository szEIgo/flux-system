#!/usr/bin/env bash
# DESCRIPTION: status
# USAGE: make status
# CATEGORY: operations
# DETAILS: flux, gwapi

set -euo pipefail

echo "kustomizations"
flux get kustomizations -A 2>/dev/null || echo "No kustomizations found"
echo ""

echo "helmreleases"
kubectl get helmrelease -A 2>/dev/null || echo "No helmreleases found"
echo ""

echo "clusterissuers"
kubectl get clusterissuer 2>/dev/null || echo "No clusterissuers found"
echo ""

echo "traefik"
kubectl -n kube-system get pods -l app.kubernetes.io/name=traefik 2>/dev/null || echo "traefik: n/a"
echo ""

echo "gatewayclass"
kubectl get gatewayclass 2>/dev/null || echo "gatewayclass: n/a"
echo ""

echo "httproute"
kubectl get httproute -A 2>/dev/null || echo "httproute: n/a"
echo ""

echo "flux"
kubectl get pods -n flux-system 2>/dev/null || echo "flux-system: n/a"

echo "cert-manager"
kubectl get pods -n cert-manager 2>/dev/null || echo "cert-manager: n/a"
