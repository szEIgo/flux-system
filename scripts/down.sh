#!/usr/bin/env bash
# DESCRIPTION: Uninstall Flux from cluster
# USAGE: make down
# CATEGORY: maintenance
# DETAILS: Removes all Flux components from the cluster

set -uo pipefail

echo "Tearing down GitOps stack..."

# Delete Flux-managed Kustomizations to prune resources
if kubectl get ns flux-system >/dev/null 2>&1; then
	echo "Deleting Flux Kustomizations (envoy-gateway, envoy-gateway-proxy, apps, flux-system)..."
	kubectl -n flux-system get kustomizations.kustomize.toolkit.fluxcd.io -o name | xargs -r kubectl -n flux-system delete --wait=false || true
fi

# Remove app namespaces
for ns in contact schmidtsgarage envoy-gateway-system cert-manager ingress-nginx openebs openebs-system zfs-localpv; do
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

# Ensure flux-system namespace finalizers are cleared
if kubectl get ns flux-system >/dev/null 2>&1; then
  kubectl patch ns flux-system -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
fi

echo "Cleaning finalizers for Terminating namespaces..."
if command -v jq >/dev/null 2>&1; then
	for ns in $(kubectl get ns --field-selector=status.phase=Terminating -o jsonpath='{.items[*].metadata.name}'); do
		echo "Cleaning finalizers for namespace: $ns"
		kubectl get ns "$ns" -o json \
			| jq '.spec.finalizers=[]' \
			| kubectl replace --raw "/api/v1/namespaces/$ns/finalize" -f - 2>/dev/null || true
	done
else
	echo "jq not found; skipping namespace finalizer cleanup loop. Install jq to enable."
fi

# Uninstall Flux controllers last
echo "Uninstalling Flux components..."
flux uninstall --silent || true

# Remove Flux namespace
kubectl delete ns flux-system --wait=false 2>/dev/null || true

# Delete cluster-scoped custom resources before CRD removal
echo "Deleting cluster-scoped custom resources (GatewayClass, ClusterIssuers)..."
# GatewayClass
kubectl get gatewayclass -o name 2>/dev/null | while read -r name; do
	kubectl patch "$name" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
	kubectl delete "$name" --wait=false 2>/dev/null || true
done
# cert-manager ClusterIssuers
kubectl get clusterissuers.cert-manager.io -o name 2>/dev/null | while read -r name; do
	kubectl patch "$name" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
	kubectl delete "$name" --wait=false 2>/dev/null || true
done

# Remove CRDs introduced by stack (Gateway API, Envoy Gateway, cert-manager)
echo "Removing CRDs for Gateway API, Envoy, cert-manager, OpenEBS, and Flux..."
kubectl get crds | awk '/gateway.networking.k8s.io|envoyproxy.io|cert-manager.io|toolkit.fluxcd.io|openebs|csi.openebs.io|zfs/ {print $1}' | xargs -r kubectl delete crd || true

echo "Removing StorageClasses created by GitOps (zfs-fast, zfs-slow)..."
kubectl delete storageclass zfs-fast zfs-slow 2>/dev/null || true
kubectl patch storageclass zfs-fast -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
kubectl patch storageclass zfs-slow -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true

echo "Deleting OpenEBS ZFS workloads in kube-system..."
kubectl -n kube-system delete statefulset openebs-zfs-controller --wait=false 2>/dev/null || true
kubectl -n kube-system delete daemonset openebs-zfs-node --wait=false 2>/dev/null || true

echo "Removing ClusterRoles and ClusterRoleBindings for Flux, Envoy, cert-manager, OpenEBS..."
kubectl get clusterrole | awk '/(^| )flux|envoy|cert-manager|openebs|zfs/ {print $1}' | xargs -r kubectl delete clusterrole || true
kubectl get clusterrolebinding | awk '/(^| )flux|envoy|cert-manager|openebs|zfs/ {print $1}' | xargs -r kubectl delete clusterrolebinding || true

echo "Removing webhook configurations for Flux, cert-manager, Envoy, OpenEBS, Metallb..."
kubectl delete mutatingwebhookconfiguration cert-manager-webhook envoy-gateway-topology-injector.envoy-gateway-system metallb-webhook-configuration 2>/dev/null || true
kubectl delete validatingwebhookconfiguration cert-manager-webhook metallb-webhook-configuration 2>/dev/null || true

echo "Ensuring GatewayClasses CRD is removed..."
kubectl delete crd gatewayclasses.gateway.networking.k8s.io 2>/dev/null || true

echo "Removing ClusterRoles and ClusterRoleBindings for Flux, Envoy, cert-manager, OpenEBS..."
kubectl get clusterrole | awk '/flux|envoy|cert-manager|openebs|zfs/ {print $1}' | xargs -r kubectl delete clusterrole || true
kubectl get clusterrolebinding | awk '/flux|envoy|cert-manager|openebs|zfs/ {print $1}' | xargs -r kubectl delete clusterrolebinding || true

echo "Removing webhook configurations for Flux, cert-manager, Envoy, OpenEBS..."
kubectl get mutatingwebhookconfigurations | awk '/flux|cert-manager|envoy|openebs|zfs/ {print $1}' | xargs -r kubectl delete mutatingwebhookconfiguration || true
kubectl get validatingwebhookconfigurations | awk '/flux|cert-manager|envoy|openebs|zfs/ {print $1}' | xargs -r kubectl delete validatingwebhookconfiguration || true

echo "Remaining namespaces:"
kubectl get ns || true
echo "Remaining CRDs (first 20):"
kubectl get crds | head -n 20 || true
echo "Remaining pods (non-system namespaces):"
kubectl get pods -A | grep -vE 'kube-system|kube-public|default|kube-node-lease' || true
echo "Remaining ClusterRoles (filtered):"
kubectl get clusterrole | grep -E 'flux|envoy|cert-manager|openebs|zfs' || true
echo "Remaining ClusterRoleBindings (filtered):"
kubectl get clusterrolebinding | grep -E 'flux|envoy|cert-manager|openebs|zfs' || true
echo "Remaining webhook configurations:"
kubectl get mutatingwebhookconfigurations || true
kubectl get validatingwebhookconfigurations || true
echo "✓ Teardown complete"
