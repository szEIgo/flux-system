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

# Remove all non-system namespaces (generic)
echo "Deleting non-system namespaces..."
for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
	case "$ns" in
		kube-system|kube-public|kube-node-lease|default)
			continue
			;;
		*)
			echo "Deleting namespace $ns..."
			# Force delete all pods in this namespace first
			kubectl -n "$ns" delete pods --all --grace-period=0 --force 2>/dev/null || true
			kubectl delete ns "$ns" --wait=false 2>/dev/null || true
			;;
	esac
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

# Force delete any stuck pods in flux-system namespace
echo "Force deleting stuck/terminating pods in flux-system..."
if kubectl get ns flux-system >/dev/null 2>&1; then
	# First strip finalizers from all pods
	kubectl -n flux-system get pods -o name 2>/dev/null | while read -r pod; do
		kubectl -n flux-system patch "$pod" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
	done
	# Then force delete terminating pods
	kubectl -n flux-system get pods --field-selector=status.phase=Terminating -o name 2>/dev/null | while read -r pod; do
		echo "Force deleting terminating pod: $pod"
		kubectl -n flux-system delete "$pod" --grace-period=0 --force 2>/dev/null || true
	done
	# Also force delete all remaining flux-system pods
	kubectl -n flux-system delete pods --all --grace-period=0 --force 2>/dev/null || true
fi

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

# Delete CoreDNS resources we installed in kube-system
echo "Removing vendor CoreDNS resources..."
kubectl -n kube-system delete deploy coredns --wait=false 2>/dev/null || true
kubectl -n kube-system delete svc kube-dns --wait=false 2>/dev/null || true
kubectl -n kube-system delete cm coredns 2>/dev/null || true
kubectl -n kube-system delete sa coredns 2>/dev/null || true
kubectl delete clusterrole system:coredns 2>/dev/null || true
kubectl delete clusterrolebinding system:coredns 2>/dev/null || true

# Delete CRDs not part of k3s defaults (generic)
echo "Removing non-default CRDs..."
# Clear CRD finalizers first
for crd in $(kubectl get crds -o jsonpath='{.items[*].metadata.name}'); do
	case "$crd" in
		addons.k3s.cattle.io|helmcharts.helm.cattle.io|helmchartconfigs.helm.cattle.io)
			continue
			;;
		*)
			kubectl patch crd "$crd" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
			;;
	esac
done
# Delete all CRDs except k3s cattle ones
kubectl get crds | awk 'NR>1 && !/addons.k3s.cattle.io|helmcharts.helm.cattle.io|helmchartconfigs.helm.cattle.io/ {print $1}' | xargs -r kubectl delete crd || true

echo "Removing StorageClasses created by GitOps (zfs-fast, zfs-slow)..."
kubectl delete storageclass zfs-fast zfs-slow 2>/dev/null || true
kubectl patch storageclass zfs-fast -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
kubectl patch storageclass zfs-slow -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true

# Generic: remove non-default StorageClasses (keep rancher local-path)
echo "Removing non-default StorageClasses (keeping local-path)..."
while IFS='|' read -r sc prov; do
	if [[ "$prov" != "rancher.io/local-path" ]]; then
		echo "Deleting StorageClass $sc (provisioner=$prov)"
		kubectl delete storageclass "$sc" 2>/dev/null || true
		kubectl patch storageclass "$sc" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
	fi
done < <(kubectl get storageclass -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.provisioner}{"\n"}{end}' 2>/dev/null)

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

# Final cleanup: force delete any remaining stuck/terminating pods
echo "Force deleting any remaining stuck pods..."
for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
	case "$ns" in
		kube-system|kube-public|kube-node-lease|default)
			continue
			;;
		*)
			# Strip finalizers from all pods in namespace
			kubectl -n "$ns" get pods -o name 2>/dev/null | while read -r pod; do
				kubectl -n "$ns" patch "$pod" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
			done
			# Force delete terminating pods
			kubectl -n "$ns" get pods --field-selector=status.phase=Terminating -o name 2>/dev/null | while read -r pod; do
				echo "Force deleting stuck pod: $pod in namespace $ns"
				kubectl -n "$ns" delete "$pod" --grace-period=0 --force 2>/dev/null || true
			done
			;;
	esac
done

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
