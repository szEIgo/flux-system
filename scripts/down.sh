#!/usr/bin/env bash
# DESCRIPTION: Uninstall Flux from cluster
# USAGE: make down
# CATEGORY: maintenance
# DETAILS: Removes all Flux components from the cluster

set -euo pipefail

echo "=== Uninstalling Flux ==="
flux uninstall --silent
echo "✓"
