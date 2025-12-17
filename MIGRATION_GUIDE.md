# Flux k3s Migration & Deployment Guide

## Current Status
Your Flux bootstrap is running but blocked on SOPS decryption. This guide walks you through:
1. ✅ Fixing the SOPS/Age decryption issue
2. ✅ Deploying infrastructure (cert-manager, ingress-nginx)
3. Migrating your podman containers to Kubernetes
4. Setting up a production-ready cluster

---

## Phase 1: Fix SOPS Decryption (IMMEDIATE PRIORITY)

### The Problem
Flux is trying to reconcile `sops-age` secret, but doesn't know which decryption provider to use. 

### The Solution
The `flux-system-kustomization.yaml` file you now have specifies the `age` decryption provider. However, **this file may need to be applied manually** if Flux hasn't bootstrapped it yet.

**Option A: Check if Flux already has this configured**
```bash
kubectl get kustomization -n flux-system -o yaml | grep -A5 "decryption:"
```

**Option B: If the decryption section is missing, apply the kustomization manually**
```bash
kubectl apply -f k8s/clusters/home/flux-system-kustomization.yaml
```

**Option C: Verify the secret exists**
```bash
kubectl get secret -n flux-system sops-age
kubectl get secret -n flux-system sops-age -o jsonpath='{.data.age\.key}' | base64 -d | head -20
```

### Troubleshooting
If you still see "SOPS encrypted" errors:
1. Ensure `sops-age` secret is in `flux-system` namespace
2. Check `.sops.yaml` has correct age recipient
3. Verify Flux has `--enable-all-flags` or specific SOPS support

---

## Phase 2: Infrastructure Deployment

### What's Being Deployed
1. **Namespaces**: `cert-manager`, `ingress-nginx`, `apps`
2. **Storage**: LocalPath provisioner (k3s default)
3. **Cert-Manager**: For SSL/TLS certificate automation
4. **Ingress-Nginx**: For HTTP/HTTPS routing

### Verify Deployment
```bash
# Check if everything reconciled
flux get kustomization -A

# Watch resources come up
kubectl get pods -n cert-manager
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx

# Check ingress controller service
kubectl get svc -n ingress-nginx ingress-nginx-controller
```

### Expected Output
```
NAMESPACE       NAME                    TYPE           EXTERNAL-IP      PORT(S)
ingress-nginx   ingress-nginx-controller  LoadBalancer   <pending|IP>     80:XXXXX/TCP,443:XXXXX/TCP
```

**Note**: `EXTERNAL-IP` may show `<pending>` on bare-metal k3s. That's normal.

---

## Phase 3: Migrate Podman Containers

### Understanding Your Container Setup
Before migrating, document your running containers:

```bash
# On your NixOS machine, find your containers
podman ps --all
podman inspect CONTAINER_ID
```

For each container, you need to know:
- **Image**: What container image (e.g., `nginx:latest`)
- **Ports**: What ports it listens on
- **Volumes**: What data it persists
- **Environment**: Environment variables needed
- **Network**: How it connects to other services

### Migration Template
Use the provided `pod-migration-template.yaml` as a starting point:

```bash
# Copy the template
cp k8s/apps/home/pod-migration-template.yaml k8s/apps/home/my-app.yaml

# Edit the template
# 1. Replace CONTAINER_NAME with your app name
# 2. Replace IMAGE:TAG with actual image
# 3. Adjust ports, volumes, environment variables
# 4. Update ingress host to your domain
```

### Example: Migrating nginx
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: apps
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
```

### Step-by-Step for Each App
1. **Create deployment.yaml**: Define pod spec, image, ports
2. **Create service.yaml**: Expose pod internally
3. **Create ingress.yaml**: Make it accessible externally (optional)
4. **Add to kustomization.yaml**: Register resources

### Organizing Multiple Apps
```
k8s/apps/home/
├── nginx/
│   ├── deployment.yaml
│   ├── service.yaml
│   └── ingress.yaml
├── postgres/
│   ├── deployment.yaml
│   ├── service.yaml
│   └── pvc.yaml
└── kustomization.yaml  # references both
```

Then in `kustomization.yaml`:
```yaml
resources:
  - ./nginx/deployment.yaml
  - ./nginx/service.yaml
  - ./nginx/ingress.yaml
  - ./postgres/deployment.yaml
  - ./postgres/service.yaml
```

---

## Phase 4: Expose Apps with Ingress

### Create Ingress Rule
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  namespace: apps
  annotations:
    cert-manager.io/cluster-issuer: "selfsigned"  # Use selfsigned first
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - myapp.local
      secretName: myapp-tls
  rules:
  - host: myapp.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-app-service
            port:
              number: 80
```

### Access Your App
```bash
# Get ingress IP
kubectl get ingress -n apps

# Add to /etc/hosts (on client machine)
echo "192.168.1.100 myapp.local" >> /etc/hosts

# Access in browser
curl https://myapp.local --insecure  # Because self-signed cert
```

---

## Phase 5: Debugging & Troubleshooting

### Common Issues

**Issue: Pod won't start**
```bash
kubectl describe pod POD_NAME -n apps
kubectl logs POD_NAME -n apps
```

**Issue: Ingress shows no IP**
```bash
kubectl get ingress -n apps -o yaml
# Check ingress-nginx logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx
```

**Issue: Secret reconciliation fails**
```bash
# Check if secret is encrypted
kubectl get secret -n infrastructure-secrets sops-age -o yaml | head -5

# Force reconciliation
flux reconcile kustomization flux-system --with-source
```

**Issue: Helm repo not reachable**
```bash
# Check HelmRepository status
kubectl get helmrepository -A

# Debug cert-manager issues
kubectl describe helmrelease cert-manager -n cert-manager
kubectl logs -n cert-manager -l app=cert-manager
```

---

## Quick Reference Commands

```bash
# Reconcile everything manually
flux reconcile kustomization flux-system --with-source

# Check reconciliation status
flux get kustomization -A
flux get helmrelease -A

# Get all resources in a namespace
kubectl get all -n apps

# Watch pod status
kubectl get pods -n apps -w

# Get cluster events
kubectl get events -A --sort-by='.lastTimestamp'

# Port-forward to test service
kubectl port-forward -n apps svc/my-app 8080:80

# Get shell in a pod
kubectl exec -it POD_NAME -n apps -- /bin/bash
```

---

## Next Steps

1. **Fix SOPS** → Run reconciliation checks above
2. **Wait for infrastructure** → Monitor cert-manager and ingress-nginx pods
3. **Prepare container list** → Document all podman containers you want to migrate
4. **Start migration** → Begin with simplest app first
5. **Test thoroughly** → Verify networking and persistence
6. **Add remaining apps** → Repeat for each container

---

## Useful Resources

- [Flux Documentation](https://fluxcd.io/docs/)
- [Kubernetes Ingress Docs](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [Cert-Manager Guide](https://cert-manager.io/docs/)
- [k3s Local Storage](https://docs.k3s.io/storage)
