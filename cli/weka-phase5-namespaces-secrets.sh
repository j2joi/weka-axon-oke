#!/usr/bin/env bash
# Phase 5: Create namespaces + Quay.io image pull secrets
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=weka-lib.sh
source "${SCRIPT_DIR}/weka-lib.sh"

phase5_namespaces_secrets() {
  log_phase 5 "Create namespaces + Quay.io image pull secrets"

  log_info "Creating namespace: weka-operator-system"
  kubectl create namespace weka-operator-system \
    --dry-run=client -o yaml \
    --kubeconfig="${KUBECONFIG_FILE}" \
  | kubectl apply -f - \
    --kubeconfig="${KUBECONFIG_FILE}"

  log_info "Creating pull secret in weka-operator-system"
  kubectl create secret docker-registry quay-io-robot-secret \
    --docker-server=quay.io \
    --docker-username="${QUAY_USERNAME}" \
    --docker-password="${QUAY_PASSWORD}" \
    --docker-email="${QUAY_USERNAME}" \
    --namespace=weka-operator-system \
    --dry-run=client -o yaml \
    --kubeconfig="${KUBECONFIG_FILE}" \
  | kubectl apply -f - \
    --kubeconfig="${KUBECONFIG_FILE}"

  log_info "Creating pull secret in default"
  kubectl create secret docker-registry quay-io-robot-secret \
    --docker-server=quay.io \
    --docker-username="${QUAY_USERNAME}" \
    --docker-password="${QUAY_PASSWORD}" \
    --docker-email="${QUAY_USERNAME}" \
    --namespace=default \
    --dry-run=client -o yaml \
    --kubeconfig="${KUBECONFIG_FILE}" \
  | kubectl apply -f - \
    --kubeconfig="${KUBECONFIG_FILE}"

  log_info "Secrets created in weka-operator-system and default namespaces."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  trap 'log_error "Script failed at line ${LINENO}. Exit code: $?"' ERR
  load_config
  check_prerequisites
  PHASES_TO_RUN=(5)
  validate_vars
  phase5_namespaces_secrets
fi
