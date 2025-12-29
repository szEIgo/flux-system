#!/usr/bin/env bash
# DESCRIPTION: logs
# USAGE: make logs
# CATEGORY: operations
# DETAILS: kustomize

set -euo pipefail

kubectl logs -n flux-system deployment/kustomize-controller -f --tail=100
