# Flux GitOps (k3s)

stack
- k3s
- traefik
- gateway-api
- flux
- sops
- cert-manager
- openebs-zfs

start
```bash
make init
GITHUB_TOKEN=... make up
make status
```

cfg
- scripts/config.sh

tree
```
k8s/
  clusters/home/
  infrastructure/
  apps/
```

secrets
- gh pat
  - GITHUB_TOKEN=... make add-gh-pat
  - cat token.txt | make add-gh-pat ARGS=--stdin
- k8s secret
  - SECRET_NAME=n SECRET_KEY=k SECRET_VALUE=v make add-secret
  - cat value.txt | make add-secret ARGS="--name n --key k --stdin"

ops
```bash
make reconcile
make logs
make down
make down ARGS="--destroy --yes"
```
