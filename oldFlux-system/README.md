# Flux GitOps - Minimal k3s Setup

Declarative k3s cluster with Flux CD, SOPS encryption, nginx-ingress, and cert-manager.

## Quick Start

```bash
make init      # Initialize SOPS encryption
make up        # Bootstrap Flux from GitHub
make status    # Check cluster health
```

## Commands

Run `make help` or `make` to see all available commands.

## Configuration

Edit `scripts/config.sh` for GitHub settings and paths.

## Structure

```
k8s/
├── clusters/home/           # Cluster entry point (Flux bootstrap path)
├── infrastructure/          # Shared infrastructure (nginx, cert-manager)
└── apps/                    # Your applications (create this)
```

## Deploy Your First App

1. Create `k8s/apps/kustomization.yaml`:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - myapp.yaml
```

2. Create your app manifest in `k8s/apps/myapp.yaml`

3. Reference apps in `k8s/clusters/home/kustomization.yaml`:
```yaml
resources:
  - storageclass_all.yaml
  - ../../infrastructure
  - ../../apps
  - cert-manager-issuers-ks.yaml
  - flux-system
```

4. Commit and push - Flux reconciles automatically.

## Network Configuration

- **Ingress**: NodePort 30080 (HTTP) / 30443 (HTTPS)
- **Host routing**: Configure your reverse proxy to forward `*.yourdomain` to these ports
- See `docs/nginx-*.conf` for example reverse proxy configs

## Secrets

```bash
make add-secret   # Create encrypted secret
```

Secrets are stored encrypted in `k8s/infrastructure/flux-system-secrets/`

## Troubleshooting

```bash
make status       # Full cluster status
make logs         # Stream Flux logs
make reconcile    # Force reconciliation
```
