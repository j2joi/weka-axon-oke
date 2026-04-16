#!/usr/bin/env bash
# Phase 4: Install WEKA operator CRDs
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=weka-lib.sh
source "${SCRIPT_DIR}/weka-lib.sh"

phase4_install_crds() {
  log_phase 4 "Install WEKA operator CRDs (${WEKA_OPERATOR_VERSION})"

  log_info "Fetching and applying CRDs from weka-operator chart..."
  helm show crds \
    oci://quay.io/weka.io/helm/weka-operator \
    --version "${WEKA_OPERATOR_VERSION}" \
  | kubectl apply --server-side -f - \
    --kubeconfig="${KUBECONFIG_FILE}"

  log_info "CRDs installed. Verifying..."
  kubectl get crds --kubeconfig="${KUBECONFIG_FILE}" | grep -i weka || true
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  trap 'log_error "Script failed at line ${LINENO}. Exit code: $?"' ERR
  load_config
  check_prerequisites
  PHASES_TO_RUN=(4)
  validate_vars
  phase4_install_crds
fi
