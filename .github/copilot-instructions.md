# AI Guide: Flux GitOps repo (k3s-friendly)

This repo declaratively bootstraps and manages a Kubernetes cluster using Flux CD v2 and SOPS (age). Use these conventions to stay productive and safe.

## Big Picture
- Flux is bootstrapped under `k8s/clusters/home/flux-system/*` (generated `gotk-*.yaml`; do not edit).
- The root of reconciliation is [`k8s/clusters/home/kustomization.yaml`](../k8s/clusters/home/kustomization.yaml): applies in order
  1) `../../infrastructure/secrets` → 2) `../../infrastructure/base` → 3) `../../apps/home`.
- Decryption uses a `sops-age` Secret in `flux-system`. Make targets automate creation and patch Flux to use SOPS server-side.

## Layout (authoritative examples)
- Apps: [`k8s/apps/home`](../k8s/apps/home) with list in [`kustomization.yaml`](../k8s/apps/home/kustomization.yaml). Template: [`pod-migration-template.yaml`](../k8s/apps/home/pod-migration-template.yaml).
- Infra (Helm + core): [`k8s/infrastructure/base`](../k8s/infrastructure/base)
  - Ingress-Nginx: [`ingress-nginx-helmrelease.yaml`](../k8s/infrastructure/base/ingress-nginx-helmrelease.yaml)
  - cert-manager + issuers: [`cert-manager-helmrelease.yaml`](../k8s/infrastructure/base/cert-manager-helmrelease.yaml), [`cert-manager-clusterissuers.yaml`](../k8s/infrastructure/base/cert-manager-clusterissuers.yaml)
  - Storage classes + namespaces: [`storage-class.yaml`](../k8s/infrastructure/base/storage-class.yaml), [`namespaces.yaml`](../k8s/infrastructure/base/namespaces.yaml)
- Secrets (SOPS-encrypted): [`k8s/infrastructure/secrets`](../k8s/infrastructure/secrets) with list in [`kustomization.yaml`](../k8s/infrastructure/secrets/kustomization.yaml). Policy: [`.sops.yaml`](../.sops.yaml).

## Workflows (use the Makefile)
- Bootstrap (after `kubectl` access):
  - `make init` → ensure age key, create `sops-age` Secret, configure decryption.
  - Optional: `make add-gh-pat` to store an encrypted GitHub token.
  - `make up` → `flux bootstrap github` pointing to `./k8s/clusters/home` and patches SOPS decryption on `flux-system` Kustomization.
- Day 2:
  - `make add-secret` → creates `*.enc.yaml` in `k8s/infrastructure/secrets/` and appends to its `kustomization.yaml`.
  - `make rotate-keys` → rotates age key and re-encrypts all secrets (and PAT if present), updates Secret in cluster.
  - `make reconcile` (force apply), `make status`, `make logs` (kustomize-controller).

## Conventions & gotchas
- Do not edit generated Flux files in [`k8s/clusters/home/flux-system`](../k8s/clusters/home/flux-system) (e.g., `gotk-components.yaml`). Commit/push to change state; use `make reconcile` to force.
- Secrets: only commit `*.enc.yaml` and `.secrets/*.sops.yaml`. Never plaintext. Decryption works server-side via the `sops-age` Secret. See [`.sops.yaml`](../.sops.yaml).
- Apps live in the `apps` namespace by default (see [`namespaces.yaml`](../k8s/infrastructure/base/namespaces.yaml)). Keep `k8s/apps/home/kustomization.yaml` as the single list of app resources.
- Ingress: NGINX via HelmRelease. Use `cert-manager.io/cluster-issuer` annotation on Ingresses (template shows `letsencrypt-prod`); update email in [`cert-manager-clusterissuers.yaml`](../k8s/infrastructure/base/cert-manager-clusterissuers.yaml).
- Helm usage pattern: each `HelmRelease` has a matching `HelmRepository` in the same namespace (see ingress-nginx and cert-manager examples).
- Storage: `local-path` (default) and `fast` classes are available (k3s-friendly).
- Note: `k8s/infrastructure/base/kustomization.yaml` references `kustomize-controller-patch.yaml` to mount the age key; if that file is absent, decryption still works because `make up` patches the Kustomization for SOPS. Prefer the Makefile workflow.

## Adding an app quickly
1) Copy [`pod-migration-template.yaml`](../k8s/apps/home/pod-migration-template.yaml) to `k8s/apps/home/myapp.yaml` and replace placeholders.
2) Append it to [`k8s/apps/home/kustomization.yaml`](../k8s/apps/home/kustomization.yaml):
   ```yaml
   resources:
     - ./myapp.yaml
   ```
3) Commit and push; watch with `make status` or `make logs`.

## Validate or debug
```bash
# Dry-run render (client-side) for a path
kustomize build k8s/apps/home

# Flux view/control
flux get kustomization -n flux-system flux-system
flux reconcile kustomization flux-system --with-source
kubectl logs -n flux-system deploy/kustomize-controller -f --tail=100
```
