# Flux GitOps (k3s-friendly)

Declarative cluster with Flux CD and SOPS (age). Minimal steps, secure defaults.

## Prerequisites

- A Kubernetes cluster (k3s/k8s) and `kubectl` configured
- Tools: `flux`, `sops`, `age` (age-keygen), optional `yq`
- GitHub repository with write access (this repo)

## Quick Start

```bash
# Optional: store your GitHub PAT encrypted (recommended)
make add-gh-pat
git add .secrets/github-pat.sops.yaml
git commit -m "Add encrypted GH PAT"
git push

# 1) Initialize SOPS in-cluster (create sops-age secret)
make init

# 2) Bootstrap Flux (uses encrypted token if present, else prompts)
make up

# 3) Verify controllers and decryption
make status
```

Tip: Your age key lives locally at `~/.config/sops/keys/age.key`. `make init` will generate or import and also update `.sops.yaml` with the public recipient.

## What’s in here

- `k8s/clusters/home/kustomization.yaml`: root that applies in order: secrets → infra → apps
- `k8s/infrastructure/base/*`: namespaces, storage, cert-manager (HelmRelease + ClusterIssuers), ingress-nginx
- `k8s/infrastructure/base/kustomize-controller-patch.yaml`: mounts the `sops-age` secret and sets `SOPS_AGE_KEY_FILE`
- `k8s/infrastructure/secrets/`: SOPS-encrypted `*.enc.yaml` files + `kustomization.yaml` listing them
- `k8s/apps/home/`: place your apps; list them in `kustomization.yaml`
- `Makefile`: one-liners for init, bootstrap, secrets, rotation, status

## Everyday tasks

Add an encrypted secret applied by Flux:

```bash
make add-secret
git add k8s/infrastructure/secrets/*.enc.yaml k8s/infrastructure/secrets/kustomization.yaml
git commit -m "Add my secret"
git push
```

Rotate the age key and re-encrypt everything:

```bash
make rotate-keys
git add .
git commit -m "Rotate SOPS age key"
git push
```

## First app

1) Create a deployment YAML (or copy a template) under `k8s/apps/home/` (e.g. `myapp.yaml`). Then list it in `k8s/apps/home/kustomization.yaml`:

```yaml
resources:
  - ./myapp.yaml
```

2) Commit and push. Flux will reconcile and deploy.

## Notes

- Ingress: ingress-nginx is a sensible default. You can switch later to Gateway API.
- cert-manager: includes ClusterIssuers; switch to DNS-01 for wildcard domains later.
- Security: only commit `*.enc.yaml` secrets and `.secrets/*.sops.yaml`. Plaintext is ignored.

## Troubleshooting

```bash
make status          # Flux Kustomization + infra pods
make logs            # kustomize-controller logs (SOPS errors show here)
make reconcile       # Force a reconciliation
```
