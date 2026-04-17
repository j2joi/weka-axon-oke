#!/usr/bin/env bash
# Phase 6: Helm install WEKA operator
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=weka-lib.sh
source "${SCRIPT_DIR}/weka-lib.sh"

phase6_helm_operator() {
  log_phase 6 "Helm install WEKA operator (${WEKA_OPERATOR_VERSION})"

  log_info "Installing weka-operator via Helm (OCI registry)..."
  helm upgrade --install weka-operator \
    oci://quay.io/weka.io/helm/weka-operator \
    --namespace weka-operator-system \
    --version "${WEKA_OPERATOR_VERSION}" \
    --set imagePullSecret=quay-io-robot-secret \
    --set csi.installationEnabled=true \
    -f deploy/operator-helm-values.yaml \
    --wait \
    --timeout 5m0s

  log_info "Waiting for weka-operator deployment to be ready..."
  kubectl rollout status deployment/weka-operator-controller-manager \
    -n weka-operator-system \
    --timeout=300s

  log_info "WEKA operator is running."
  kubectl get pods -n weka-operator-system
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  trap 'log_error "Script failed at line ${LINENO}. Exit code: $?"' ERR
  load_config
  PHASES_TO_RUN=(6)
  check_prerequisites
  validate_vars
  phase6_helm_operator
fi
