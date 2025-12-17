# Flux k3s GitOps

Declarative Kubernetes cluster management with Flux and SOPS encryption.

## Prerequisites

- k3s running
- kubectl configured
- Age key at: `~/.config/sops/keys/age.key`
- GitHub Personal Access Token (fine-grained, repo contents:read/write)

## Quick Start

```bash
# 1. Bootstrap Flux
make up
# When prompted, paste your GitHub PAT

# 2. Setup SOPS decryption
make sops

# 3. Verify
make status
```

## Make Commands

| Command | Purpose |
|---------|---------|
| `make up` | Bootstrap Flux from GitHub |
| `make sops` | Setup SOPS decryption |
| `make reconcile` | Force reconciliation |
| `make status` | Check Flux status |
| `make logs` | Watch Flux logs |
| `make down` | Uninstall Flux |
| `make clean` | Remove SOPS secret |

## How It Works

```
Git Repository (GitHub)
    ↓
Flux reads k8s/clusters/home/kustomization.yaml
    ↓
Deploys: secrets → infrastructure (cert-manager, ingress-nginx) → apps
    ↓
SOPS decrypts age-secret.yaml using your age.key
    ↓
Cluster reconciles to desired state
```

## Structure

```
k8s/
├── clusters/home/              # Root kustomization
│   └── kustomization.yaml
├── infrastructure/
│   ├── base/                   # cert-manager, ingress-nginx
│   │   ├── cert-manager-helmrelease.yaml
│   │   ├── cert-manager-clusterissuers.yaml
│   │   ├── ingress-nginx-helmrelease.yaml
│   │   ├── namespaces.yaml
│   │   └── storage-class.yaml
│   └── secrets/
│       ├── age-secret.yaml     # SOPS-encrypted
│       └── kustomization.yaml
└── apps/home/                  # Your deployments
    ├── kustomization.yaml
    └── pod-migration-template.yaml
```

## Deploy Applications

1. Copy template: `cp k8s/apps/home/pod-migration-template.yaml k8s/apps/home/myapp.yaml`
2. Edit with your image, ports, volumes
3. Add to `k8s/apps/home/kustomization.yaml` resources
4. Commit & push: `git add . && git commit -m "Add myapp" && git push`
5. Flux auto-deploys within 1 minute

## Troubleshoot

```bash
# Check Flux status
make status

# Watch logs
make logs

# Force sync
make reconcile

# Check specific pod logs
kubectl logs -n flux-system deployment/kustomize-controller
```
