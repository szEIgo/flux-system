# Flux GitOps Setup

## Commands

```bash
make init      # Initialize SOPS encryption
make up        # Bootstrap Flux from GitHub
make status    # Check cluster health
make reconcile # Force reconcile
make logs      # View Flux logs
make clean     # Clean up
```

## Structure

- `k8s/clusters/home/` - Cluster entry point
- `k8s/infrastructure/` - Infrastructure components
- `k8s/apps/` - Applications
- `k8s/secrets/` - Secrets