#!/usr/bin/env bash
# DESCRIPTION: Force Flux to reconcile immediately
# USAGE: make reconcile
# CATEGORY: operations
# DETAILS: Triggers immediate reconciliation of flux-system Kustomization

set -euo pipefail

echo "Reconciling Flux..."
flux reconcile kustomization flux-system --with-source
echo "✓"
