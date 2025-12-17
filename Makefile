.PHONY: up down sops reconcile status logs clean help

GITHUB_OWNER := szeigo
GITHUB_REPO := flux-system
GITHUB_BRANCH := main
FLUX_PATH := ./k8s/clusters/home
AGE_KEY := $(HOME)/.config/sops/keys/age.key

help:
	@echo "Flux GitOps with SOPS Makefile"
	@echo ""
	@echo "Usage:"
	@echo "  make up         - Bootstrap Flux from GitHub"
	@echo "  make sops       - Setup SOPS decryption (run after 'make up')"
	@echo "  make reconcile  - Force Flux reconciliation"
	@echo "  make status     - Check Flux status"
	@echo "  make logs       - Watch Flux logs"
	@echo "  make down       - Uninstall Flux"
	@echo "  make clean      - Remove SOPS secret"

up:
	@echo "=== Bootstrapping Flux from GitHub ==="
	flux bootstrap github \
		--owner=$(GITHUB_OWNER) \
		--repo=$(GITHUB_REPO) \
		--branch=$(GITHUB_BRANCH) \
		--path=$(FLUX_PATH) \
		--personal
	@echo ""
	@echo "✓ Bootstrap complete. Now run: make sops"

sops:
	@echo "=== Setting up SOPS decryption ==="
	@if [ ! -f "$(AGE_KEY)" ]; then \
		echo "ERROR: Age key not found at $(AGE_KEY)"; \
		exit 1; \
	fi
	@echo "Step 1: Creating sops-age secret..."
	kubectl create secret generic sops-age \
		--from-file=age.key=$(AGE_KEY) \
		-n flux-system \
		--dry-run=client -o yaml | kubectl apply -f -
	@echo "Step 2: Configuring SOPS provider..."
	kubectl patch kustomization flux-system -n flux-system \
		--type merge -p '{"spec":{"decryption":{"provider":"sops","secretRef":{"name":"sops-age"}}}}'
	@echo "Step 3: Patching kustomize-controller to find age key..."
	kubectl set env deployment/kustomize-controller \
		-n flux-system \
		SOPS_AGE_KEY_FILE=/var/secrets/sops/age.key || true
	kubectl patch deployment kustomize-controller -n flux-system --type json -p='[ \
		{"op":"add","path":"/spec/template/spec/volumes/-","value":{"name":"sops-age","secret":{"secretName":"sops-age"}}}, \
		{"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-","value":{"name":"sops-age","mountPath":"/var/secrets/sops","readOnly":true}} \
	]' || true
	@echo "Step 4: Reconciling..."
	flux reconcile kustomization flux-system --with-source
	@echo "✓ SOPS setup complete"

reconcile:
	@echo "=== Reconciling Flux ==="
	flux reconcile kustomization flux-system --with-source
	@echo "✓ Reconciliation triggered"

status:
	@echo "=== Flux Status ==="
	@flux get kustomization -n flux-system flux-system
	@echo ""
	@echo "=== Infrastructure Pods ==="
	@kubectl get pods -n cert-manager 2>/dev/null || echo "cert-manager: not deployed"
	@kubectl get pods -n ingress-nginx 2>/dev/null || echo "ingress-nginx: not deployed"
	@kubectl get pods -n apps 2>/dev/null || echo "apps: namespace exists"

logs:
	@echo "=== Flux Logs (kustomize-controller) ==="
	kubectl logs -n flux-system deployment/kustomize-controller -f --tail=50

down:
	@echo "=== Uninstalling Flux ==="
	flux uninstall --silent
	@echo "✓ Flux uninstalled"

clean:
	@echo "=== Removing SOPS secret ==="
	kubectl delete secret sops-age -n flux-system 2>/dev/null || echo "Secret not found"
	@echo "✓ Cleaned"
