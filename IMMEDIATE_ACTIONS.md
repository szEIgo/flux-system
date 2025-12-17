# Immediate Action Items

## 🔴 CRITICAL - Fix SOPS Right Now

Your Flux bootstrap is stuck because it can't decrypt secrets. Do this immediately:

```bash
# 1. Verify the secret exists
kubectl get secret -n flux-system sops-age -o yaml

# 2. Check if Flux has decryption configured
kubectl get kustomization -n flux-system flux-system -o yaml | grep -A10 "decryption:"

# 3. If decryption section is MISSING, apply the fix:
kubectl apply -f k8s/clusters/home/flux-system-kustomization.yaml

# 4. Force reconciliation to pick up the decryption config
flux reconcile kustomization flux-system --with-source

# 5. Watch for reconciliation success
flux get kustomization -n flux-system flux-system --watch
```

## Expected Success Signs
✅ Kustomization "flux-system" reconciles successfully  
✅ No more "SOPS encrypted, configuring decryption is required" errors  
✅ You see pods coming up in `cert-manager` and `ingress-nginx` namespaces

---

## 📋 Then: Document Your Containers

Before migrating, create a spreadsheet of your podman containers:

```bash
# List all containers
podman ps -a --format "table {{.ID}}\t{{.Image}}\t{{.Names}}\t{{.Ports}}"

# For each container, gather details:
podman inspect CONTAINER_NAME | jq '.[] | {
  Image: .Config.Image,
  Env: .Config.Env,
  ExposedPorts: .Config.ExposedPorts,
  Volumes: .Config.Volumes,
  WorkingDir: .Config.WorkingDir
}'
```

### Container Info Template
Create a file called `CONTAINERS.md`:

```markdown
# Podman Containers to Migrate

## app1
- Image: app1:v1.2
- Ports: 8080 -> 8080
- Volumes: /data -> /var/lib/app1
- Env: DEBUG=true, APP_NAME=app1
- Status: Ready for migration

## app2
- Image: app2:latest
- Ports: 3000 -> 3000
- Volumes: /config -> /etc/app2
- Dependencies: postgres, redis
- Status: Needs update first
```

---

## 🚀 Quick Migration Playbook

Once SOPS is fixed:

### Step 1: Deploy Infrastructure (should happen automatically)
```bash
kubectl get pods -n cert-manager
kubectl get pods -n ingress-nginx
# Wait until all show "Running"
```

### Step 2: Start with Simplest App
Pick one app (e.g., a web service that doesn't need a database).

```bash
# Create app directory
mkdir -p k8s/apps/home/my-first-app

# Copy and edit template
cp k8s/apps/home/pod-migration-template.yaml \
   k8s/apps/home/my-first-app/deployment.yaml

# Edit the file with your app details
nano k8s/apps/home/my-first-app/deployment.yaml
```

### Step 3: Register with Kustomization
Edit `k8s/apps/home/kustomization.yaml`:

```yaml
resources:
  - ./my-first-app/deployment.yaml
```

### Step 4: Commit and Push
```bash
cd /home/joni/flux-system
git add .
git commit -m "Add my-first-app migration"
git push
```

### Step 5: Watch Flux Deploy It
```bash
kubectl get deployments -n apps --watch
kubectl get pods -n apps -w
```

---

## 📊 Overall Structure (What You Now Have)

```
flux-system/
├── .sops.yaml                    # SOPS encryption config ✅
├── k8s/
│   ├── clusters/home/
│   │   ├── kustomization.yaml   # Root orchestrator ✅
│   │   └── flux-system-kustomization.yaml  # NEW: Decryption config ✅
│   │
│   ├── infrastructure/
│   │   ├── base/
│   │   │   ├── kustomization.yaml             ✅
│   │   │   ├── namespaces.yaml                ✅ NEW
│   │   │   ├── storage-class.yaml             ✅ NEW
│   │   │   ├── cert-manager-helmrelease.yaml  ✅ NEW
│   │   │   └── ingress-nginx-helmrelease.yaml ✅ NEW
│   │   └── secrets/
│   │       ├── age-secret.yaml                (SOPS encrypted)
│   │       ├── github-pat-secret.yaml
│   │       └── kustomization.yaml
│   │
│   └── apps/home/
│       ├── kustomization.yaml                 ✅ Updated
│       ├── pod-migration-template.yaml        ✅ NEW
│       └── [YOUR APPS GO HERE]
│
└── MIGRATION_GUIDE.md            ✅ NEW
```

---

## ⚠️ Troubleshooting Reference

**Problem**: "apiserver not ready" errors in logs
- **Cause**: k3s is still booting or crashed
- **Fix**: Check k3s service status: `systemctl status k3s`

**Problem**: Pods stuck in Pending
- **Cause**: Storage class issue or node resource constraints
- **Fix**: `kubectl describe pod POD_NAME -n apps`

**Problem**: Ingress shows no address
- **Cause**: LoadBalancer IP not assigned (normal for bare metal)
- **Fix**: Use NodePort or configure MetalLB

**Problem**: "Already Exists" errors
- **Cause**: Resource created by different process
- **Fix**: Delete and re-apply: `kubectl delete -f file.yaml && kubectl apply -f file.yaml`

---

## 🎯 Success Metrics

- [ ] Kustomization `flux-system` reconciles without errors
- [ ] Cert-manager pod running in `cert-manager` namespace
- [ ] Ingress-nginx controller running in `ingress-nginx` namespace
- [ ] First app deployed successfully
- [ ] Can access app via ingress URL
- [ ] All pods have persistent volume claims working

---

## Commands Cheat Sheet

```bash
# Get everything status
flux get all -A

# Reconcile manually
flux reconcile kustomization flux-system --with-source

# See all resources
kubectl get all -A | grep -v kube

# Logs
kubectl logs -f deployment/my-app -n apps

# Shell access
kubectl exec -it deployment/my-app -n apps -- /bin/bash

# Port forward
kubectl port-forward svc/my-app 8080:80 -n apps
```
