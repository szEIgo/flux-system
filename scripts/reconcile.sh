#!/usr/bin/env bash
# DESCRIPTION: reconcile
# USAGE: make reconcile
# CATEGORY: operations
# DETAILS: flux

set -euo pipefail

echo "Reconciling Flux..."
flux reconcile kustomization flux-system --with-source
echo "✓"
