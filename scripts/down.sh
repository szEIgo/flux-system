#!/usr/bin/env bash
# DESCRIPTION: Uninstall Flux from cluster
# USAGE: make down
# CATEGORY: maintenance
# DETAILS: Removes all Flux components from the cluster

set -euo pipefail

echo "Tearing down GitOps stack..."

# Delete Flux-managed Kustomizations to prune resources
if kubectl get ns flux-system >/dev/null 2>&1; then
	echo "Deleting Flux Kustomizations (envoy-gateway, envoy-gateway-proxy, apps, flux-system)..."
	kubectl -n flux-system get kustomizations.kustomize.toolkit.fluxcd.io -o name | xargs -r kubectl -n flux-system delete --wait=false || true
fi

# Remove app namespaces
for ns in contact schmidtsgarage envoy-gateway-system cert-manager ingress-nginx; do
	if kubectl get ns "$ns" >/dev/null 2>&1; then
		echo "Deleting namespace $ns..."
		kubectl delete ns "$ns" --wait=false || true
	fi
done

# Strip finalizers from stuck resources across common groups
echo "Stripping finalizers from stuck resources..."
strip_finalizers() {
	kinds=(secrets configmaps services deployments statefulsets daemonsets ingresses gateways httproutes certificates)
	for kind in "${kinds[@]}"; do
		for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
			kubectl get "$kind" -n "$ns" -o name 2>/dev/null | while read -r name; do
				kubectl patch "$name" -n "$ns" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
			done
		done
	done
}
strip_finalizers

# Uninstall Flux controllers last
echo "Uninstalling Flux components (including CRDs)..."
flux uninstall --silent --crds || true

# Remove Flux namespace
kubectl delete ns flux-system --wait=false 2>/dev/null || true

# Remove CRDs introduced by stack (Gateway API, Envoy Gateway, cert-manager)
echo "Removing CRDs for Gateway API, Envoy, cert-manager, and Flux..."
kubectl get crds | awk '/gateway.networking.k8s.io|envoyproxy.io|cert-manager.io|toolkit.fluxcd.io/ {print $1}' | xargs -r kubectl delete crd || true

echo "✓ Teardown complete"
