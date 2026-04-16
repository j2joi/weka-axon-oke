#!/usr/bin/env bash
# Phase 3: Label worker nodes as WEKA clients (weka.io/supports-clients=true)
#
# Usage (standalone): ./weka-phase3-label-clients.sh node1 [node2 ...]
#   node1 ...   Labels only the specified nodes as clients.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=weka-lib.sh
source "${SCRIPT_DIR}/weka-lib.sh"

print_usage_clients() {
  echo ""
  echo "Usage: $0 node1 [node2 ...]"
  echo ""
  echo "  Labels the specified nodes with weka.io/supports-clients=true."
  echo "  At least one node name is required."
  echo ""
  echo "Backend worker nodes for converge in the cluster:"
      echo ""
      kubectl get nodes \
        --selector='!node-role.kubernetes.io/control-plane,weka.io/supports-backends' \
        --kubeconfig="${KUBECONFIG_FILE}" 2>/dev/null \
        || echo "  (could not reach cluster — verify KUBECONFIG_FILE=${KUBECONFIG_FILE})"
  echo ""
  echo "Non-backend worker nodes in the cluster:"
  echo ""
  kubectl get nodes \
    --selector='!node-role.kubernetes.io/control-plane,!weka.io/supports-backends' \
    --kubeconfig="${KUBECONFIG_FILE}" 2>/dev/null \
    || echo "  (could not reach cluster — verify KUBECONFIG_FILE=${KUBECONFIG_FILE})"
  echo ""

}

phase3_label_clients() {
  log_phase 3 "Label client nodes (weka.io/supports-clients=true)"

  log_info "Waiting for all nodes to reach Ready state (timeout: 300s)..."
  kubectl wait --for=condition=Ready nodes --all \
    --timeout=300s \
    --kubeconfig="${KUBECONFIG_FILE}"

  local -a client_nodes=("${LABEL_CLIENT_NODES[@]}")

  log_info "Applying weka.io/supports-clients=true to: ${client_nodes[*]}"
  kubectl label node "${client_nodes[@]}" \
    weka.io/supports-clients=true \
    --overwrite \
    --kubeconfig="${KUBECONFIG_FILE}"

  log_info "Client node labels:"
  kubectl get nodes --show-labels \
    --kubeconfig="${KUBECONFIG_FILE}" | grep -E "NAME|weka\.io/supports-clients"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  trap 'log_error "Script failed at line ${LINENO}. Exit code: $?"' ERR

  load_config
  check_prerequisites

  if [[ $# -eq 0 || "$1" == "--help" || "$1" == "-h" ]]; then
    print_usage_clients
    exit 0
  fi

  LABEL_CLIENT_NODES=("$@")
  PHASES_TO_RUN=(3)
  validate_vars
  phase3_label_clients
fi
