#!/usr/bin/env bash
# Phase 8: Deploy WekaCluster CR
#
# Usage (standalone): ./weka-phase8-create-cluster.sh [-d]
#   -d   Dry-run: generate YAML manifest but skip kubectl apply.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=weka-lib.sh
source "${SCRIPT_DIR}/weka-lib.sh"

phase8_create_cluster() {
  log_phase 8 "Deploy WekaCluster CR"

  mkdir -p "${DEPLOY_DIR}"
  local manifest="${DEPLOY_DIR}/weka-cluster.yaml"

#  log_info "Generating ${manifest}"
#  cat > "${manifest}" << EOF
#apiVersion: weka.weka.io/v1alpha1
#kind: WekaCluster
#metadata:
#  name: cluster-dev
#  namespace: default
#spec:
#  template: dynamic
#  dynamicTemplate:
#    computeContainers: 6
#    driveContainers: 6
#    computeCores: 2
#    driveCores: 1
#    numDrives: 1
##    containerCapacity: 1000
#  image: ${WEKA_IMAGE}
#  nodeSelector:
#    weka.io/supports-backends: "true"
#  driversDistService: https://drivers.weka.io
#  imagePullSecret: "quay-io-robot-secret"
#  ports:
#    basePort: 15000
#    portRange: 500
#  network:
#    udpMode: true
#EOF

  log_info "Applying WekaCluster CR..."
  kubectl_apply "${manifest}"
  [[ "${DRY_RUN}" == "true" ]] && return

  log_info "WekaCluster applied. Current status:"
  kubectl get wekacluster cluster-dev \
    -n default \
    --kubeconfig="${KUBECONFIG_FILE}" 2>/dev/null || true
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
  check_prerequisites
  PHASES_TO_RUN=(8)
  validate_vars
  phase8_create_cluster
fi
