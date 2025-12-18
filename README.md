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

## Available Commands

Run `make help` to see all available commands with descriptions. Commands are organized by category:

- **Setup & Bootstrap**: `init`, `up`
- **Secrets Management**: `add-gh-pat`, `add-secret`
- **Day-to-Day Operations**: `reconcile`, `status`, `logs`
- **Maintenance**: `rotate-keys`, `down`, `clean`

## Common Tasks

### Add an encrypted secret

```bash
make add-secret
# Follow prompts: filename, key name, value
git add k8s/infrastructure/flux-system-secrets/*.enc.yaml
git add k8s/infrastructure/flux-system-secrets/kustomization.yaml
git commit -m "Add my secret"
git push
```

### Rotate the age encryption key

```bash
make rotate-keys
git add .sops.yaml k8s/infrastructure/flux-system-secrets/*.enc.yaml
git commit -m "Rotate SOPS age key"
git push
```

### Force reconciliation

```bash
make reconcile
```

### Check status

```bash
make status
```

## Architecture

### Reconciliation Flow

```
Root (k8s/kustomization.yaml)
├── clusters/home/
│   ├── cluster-config.yaml (storage classes)
│   └── flux-system/ (generated)
└── infrastructure/
    ├── nginx-ingress/
    ├── cert-manager/
    └── flux-system-secrets/
```

### Infrastructure Components

- **nginx-ingress**: HelmRelease with v4.10.0+, LoadBalancer service (uses k3s servicelb)
- **cert-manager**: HelmRelease with v1.15.0+, includes ClusterIssuers:
  - `selfsigned`: For internal/development certificates
  - `letsencrypt-prod`: For production domains with HTTP-01 challenge
- **Storage**: Two StorageClasses using k3s local-path provisioner (`local-path`, `fast`)

### Security

- **Encryption**: All secrets are SOPS-encrypted with age
- **Git Safety**: Only commit `*.enc.yaml` secrets. Plaintext is ignored via `.gitignore`
- **Age Key**: Stored locally at `~/.config/sops/keys/age.key` (never committed)
- **In-Cluster**: `sops-age` Secret in `flux-system` namespace for server-side decryption

## Troubleshooting

```bash
make status          # Flux Kustomization + infra pods
make logs            # kustomize-controller logs (SOPS errors show here)
make reconcile       # Force a reconciliation
```
