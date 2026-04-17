#!/usr/bin/env bash
# Phase 2: Extract kubeconfig from Terraform output
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=weka-lib.sh
source "${SCRIPT_DIR}/weka-lib.sh"

phase2_kubeconfig() {
  log_phase 2 "Extract kubeconfig from Terraform output"

  mkdir -p "${DEPLOY_DIR}"

  cd "${TF_DIR}"

  # cluster_kubeconfig is an object (not a plain string), so -raw is not
  # supported. Write the JSON directly — kubectl accepts JSON kubeconfigs.
  local kubeconfig_content
  kubeconfig_content="$(terraform output -json cluster_kubeconfig)"

  if [[ -z "${kubeconfig_content}" || "${kubeconfig_content}" == "null" ]]; then
    log_error "Could not extract kubeconfig from Terraform output."
    log_error "Run 'terraform output -json cluster_kubeconfig' to inspect the structure."
    exit 1
  fi

  local kubeconfig_path="${DEPLOY_DIR}/kubeconfig"
  echo "${kubeconfig_content}" > "${kubeconfig_path}"
  chmod 600 "${kubeconfig_path}"
  export KUBECONFIG="${kubeconfig_path}"

  log_info "Verifying cluster connectivity..."
  kubectl cluster-info

  echo "export KUBECONFIG=${kubeconfig_path}" > "${DEPLOY_DIR}/env.sh"

  log_info "Kubeconfig saved to: ${kubeconfig_path}"
  cd "${PROJECT_ROOT}"

  echo ""
  echo "  ┌─ To use kubectl without --kubeconfig on every call, choose one option:"
  echo "  │"
  echo "  │  Option A — source into current shell (no copy-paste needed):"
  echo "  │    source ${DEPLOY_DIR}/env.sh"
  echo "  │"
  echo "  │  Option A — or set it inline right now:"
  echo "  │    export KUBECONFIG=${kubeconfig_path}"
  echo "  │"
  echo "  │  Option B — merge permanently into ~/.kube/config:"
  echo "  │    KUBECONFIG=~/.kube/config:${kubeconfig_path} kubectl config view --flatten > /tmp/merged && mv /tmp/merged ~/.kube/config"
  echo "  │    kubectl config use-context weka-param-tf"
  echo "  └──────────────────────────────────────────────────────────────────"
  echo ""
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  trap 'log_error "Script failed at line ${LINENO}. Exit code: $?"' ERR
  load_config
  PHASES_TO_RUN=(2)
  check_prerequisites
  validate_vars
  phase2_kubeconfig
fi
