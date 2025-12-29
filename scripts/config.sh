#!/usr/bin/env bash
# Configuration for Flux GitOps scripts
# Source this file in other scripts: source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

# GitHub repository settings
export GITHUB_OWNER="${GITHUB_OWNER:-szeigo}"
export GITHUB_REPO="${GITHUB_REPO:-flux-system}"
export GITHUB_BRANCH="${GITHUB_BRANCH:-nginx}"

# Paths
export FLUX_PATH="./k8s/clusters/home"
export AGE_KEY="${HOME}/.config/sops/keys/age.key"
export SECRETS_DIR="k8s/infrastructure/flux-system-secrets"
export KUSTOMIZATION_FILE="${SECRETS_DIR}/kustomization.yaml"

# Sensitive files (not in config, handled by individual scripts)
# - GITHUB_TOKEN_FILE (handled by add-gh-pat.sh and bootstrap.sh)
# - Secret values (handled interactively)
