#!/usr/bin/env bash
# config

# GitHub repository settings
export GITHUB_OWNER="${GITHUB_OWNER:-szeigo}"
export GITHUB_REPO="${GITHUB_REPO:-flux-system}"
export GITHUB_BRANCH="${GITHUB_BRANCH:-main}"

# Namespaces
export FLUX_NAMESPACE="${FLUX_NAMESPACE:-flux-system}"

# Paths
export FLUX_PATH="./k8s/clusters/home"
export AGE_KEY="${HOME}/.config/sops/keys/age.key"
export SECRETS_DIR="k8s/infrastructure/flux-system-secrets"
export KUSTOMIZATION_FILE="${SECRETS_DIR}/kustomization.yaml"

# Files
export SOPS_RULES_FILE="${SOPS_RULES_FILE:-.sops.yaml}"
export GITHUB_TOKEN_SOPS_FILE="${GITHUB_TOKEN_SOPS_FILE:-.secrets/github-pat.sops.yaml}"

# Secrets
# - GITHUB_TOKEN: env only
# - SECRET_VALUE: env/stdin/file
