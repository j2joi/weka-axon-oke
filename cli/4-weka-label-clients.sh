#!/usr/bin/env bash
# Phase 3: Label worker nodes as WEKA clients (weka.io/supports-clients=true)
#
# Usage (standalone):
#   ./weka-phase3-label-clients.sh --all              Label all worker nodes
#   ./weka-phase3-label-clients.sh --first N          Label the first N worker nodes
#   ./weka-phase3-label-clients.sh node1 [node2 ...]  Label specific nodes by name
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=weka-lib.sh
source "${SCRIPT_DIR}/weka-lib.sh"

# Returns one node name per line (worker nodes only, no control-plane)
get_worker_nodes() {
  kubectl get nodes \
    --selector='!node-role.kubernetes.io/control-plane' \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
    2>/dev/null | grep -v '^$' || true
}

print_usage_clients() {
  echo ""
  echo "Usage: $0 [OPTIONS] [node1 node2 ...]"
  echo ""
  echo "Options:"
  echo "  --all         Label all worker nodes as clients"
  echo "  --first N     Label the first N worker nodes as clients"
  echo "  -h, --help    Show this help"
  echo ""
  echo "Arguments:"
  echo "  node1 [node2 ...]   Label specific nodes by name"
  echo ""
  echo "Backend worker nodes in the cluster:"
  echo ""
  kubectl get nodes \
    --selector='!node-role.kubernetes.io/control-plane,weka.io/supports-backends' \
    2>/dev/null \
    || echo "  (could not reach cluster — verify KUBECONFIG is set)"
  echo ""
  echo "Non-backend worker nodes in the cluster:"
  echo ""
  kubectl get nodes \
    --selector='!node-role.kubernetes.io/control-plane,!weka.io/supports-backends' \
    2>/dev/null \
    || echo "  (could not reach cluster — verify KUBECONFIG is set)"
  echo ""
}

phase3_label_clients() {
  log_phase 3 "Label client nodes (weka.io/supports-clients=true)"

  log_info "Waiting for all nodes to reach Ready state (timeout: 300s)..."
  kubectl wait --for=condition=Ready nodes --all \
    --timeout=300s

  local -a client_nodes=("${LABEL_CLIENT_NODES[@]}")

  log_info "Applying weka.io/supports-clients=true to: ${client_nodes[*]}"
  kubectl label node "${client_nodes[@]}" \
    weka.io/supports-clients=true \
    --overwrite

  log_info "Client node labels:"
#  kubectl get nodes --show-labels | grep -E "NAME|weka\.io/supports-clients"
  kubectl get nodes -L "weka.io/supports-clients"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  trap 'log_error "Script failed at line ${LINENO}. Exit code: $?"' ERR

  load_config
  PHASES_TO_RUN=(3)
  check_prerequisites

  if [[ $# -eq 0 || "$1" == "--help" || "$1" == "-h" ]]; then
    print_usage_clients
    exit 0
  fi

  LABEL_CLIENT_NODES=()

  case "$1" in
    --all)
      while IFS= read -r node; do
        LABEL_CLIENT_NODES+=("${node}")
      done < <(get_worker_nodes)
      if [[ ${#LABEL_CLIENT_NODES[@]} -eq 0 ]]; then
        log_error "No worker nodes found in the cluster."
        exit 1
      fi
      log_info "Targeting all ${#LABEL_CLIENT_NODES[@]} worker nodes."
      ;;
    --first)
      if [[ $# -lt 2 || ! "$2" =~ ^[0-9]+$ || "$2" -eq 0 ]]; then
        log_error "--first requires a positive integer argument."
        exit 1
      fi
      all_nodes=()
      while IFS= read -r node; do
        all_nodes+=("${node}")
      done < <(get_worker_nodes)
      total_nodes=${#all_nodes[@]}
      n_nodes="$2"
      if [[ ${n_nodes} -gt ${total_nodes} ]]; then
        log_error "--first ${n_nodes}: only ${total_nodes} worker node(s) available. N must be less than or equal to ${total_nodes}."
        exit 1
      fi
      LABEL_CLIENT_NODES=("${all_nodes[@]:0:${n_nodes}}")
      log_info "Targeting first ${n_nodes} of ${total_nodes} worker nodes."
      ;;
    -*)
      log_error "Unknown option: $1"
      print_usage_clients
      exit 1
      ;;
    *)
      LABEL_CLIENT_NODES=("$@")
      ;;
  esac

  validate_vars
  phase3_label_clients
fi
