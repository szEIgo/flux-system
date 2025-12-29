#!/usr/bin/env bash
# DESCRIPTION: Show comprehensive cluster and Flux status
# USAGE: make status
# CATEGORY: operations
# DETAILS: Displays all Kustomizations, HelmReleases, ClusterIssuers, and pod status

set -euo pipefail

echo "Flux Kustomizations:"
flux get kustomizations -A 2>/dev/null || echo "No kustomizations found"
echo ""

echo "Helm Releases:"
kubectl get helmrelease -A 2>/dev/null || echo "No helmreleases found"
echo ""

echo "Cert-Manager ClusterIssuers:"
kubectl get clusterissuer 2>/dev/null || echo "No clusterissuers found"
echo ""

echo "Infrastructure Pods:"
kubectl get pods -n cert-manager 2>/dev/null || echo "cert-manager: not deployed"
kubectl get pods -n ingress-nginx 2>/dev/null || echo "ingress-nginx: not deployed"
echo ""

echo "Flux System Pods:"
kubectl get pods -n flux-system 2>/dev/null || echo "flux-system: not deployed"
