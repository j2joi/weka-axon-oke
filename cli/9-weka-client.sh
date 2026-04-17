#!/usr/bin/env bash
# Phase 9: Deploy WekaClient CR
#
# Usage (standalone): ./9-weka-client.sh [-d]
#   -d   Dry-run: generate YAML manifest but skip kubectl apply.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=weka-lib.sh
source "${SCRIPT_DIR}/weka-lib.sh"

phase9_weka_client() {
  log_phase 9 "Deploy WekaClient CR"

  mkdir -p "${DEPLOY_DIR}"
  local manifest="${DEPLOY_DIR}/weka-client.yaml"

#  log_info "Generating ${manifest}"
#  cat > "${manifest}" << EOF
#apiVersion: weka.weka.io/v1alpha1
#kind: WekaClient
#metadata:
#  name: cluster-clients
#  namespace: default
#spec:
#  image: ${WEKA_IMAGE}
#  imagePullSecret: "quay-io-robot-secret"
#  driversDistService: "https://drivers.weka.io"
#  portRange:
#    basePort: ${BASE_PORT}
#  nodeSelector:
#    weka.io/supports-clients: "true"
#  wekaSecretRef: weka-client-cluster-dev
#  targetCluster:
#    name: cluster-dev
#    namespace: default
#EOF

  log_info "Applying WekaClient..."
  kubectl_apply "${manifest}"
  [[ "${DRY_RUN}" == "true" ]] && return

  log_info "WekaClient applied. Waiting for pods to start..."
  sleep 10

  log_info "WekaClient status:"
  kubectl get wekaclient cluster-clients \
    -n default \
    2>/dev/null || true

  log_info "WEKA client pods:"
  kubectl get pods -n default \
    2>/dev/null || true

  log_info "Deployment complete."
  echo ""
  echo "  To monitor WEKA pods:"
  echo "    kubectl get pods -n default -w"
  echo ""
  echo "  To check operator logs:"
  echo "    kubectl logs -n weka-operator-system deploy/weka-operator"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  trap 'log_error "Script failed at line ${LINENO}. Exit code: $?"' ERR

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -d) DRY_RUN=true; shift ;;
      --help|-h) echo "Usage: $0 [-d]"; echo "  -d  Dry-run: generate YAML only, skip kubectl apply."; exit 0 ;;
      *) log_error "Unknown argument: $1"; exit 1 ;;
    esac
  done

  load_config
  PHASES_TO_RUN=(9)
  check_prerequisites
  validate_vars
  phase9_weka_client
fi
