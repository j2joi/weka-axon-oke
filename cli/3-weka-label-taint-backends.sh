#!/usr/bin/env bash
# Phase 3: Label and taint worker nodes as WEKA backends
#   Label : weka.io/supports-backends=true
#   Taint : weka.io/axon=true:NoSchedule
#
# Usage (standalone):
#   ./3-weka-label-taint-backends.sh --all              Label+taint all worker nodes
#   ./3-weka-label-taint-backends.sh --first N          Label+taint the first N worker nodes
#   ./3-weka-label-taint-backends.sh node1 [node2 ...]  Label+taint specific nodes by name
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

print_usage_backends() {
  echo ""
  echo "Usage: $0 [OPTIONS] [node1 node2 ...]"
  echo ""
  echo "Options:"
  echo "  --all         Label+taint all worker nodes as backends"
  echo "  --first N     Label+taint the first N worker nodes as backends"
  echo "  -h, --help    Show this help"
  echo ""
  echo "Arguments:"
  echo "  node1 [node2 ...]   Label+taint specific nodes by name"
  echo ""
  echo "Each selected node receives:"
  echo "  label : weka.io/supports-backends=true"
  echo "  taint : weka.io/axon=true:NoSchedule"
  echo ""
  echo "Available worker nodes in the cluster:"
  echo ""
  kubectl get nodes \
    --selector='!node-role.kubernetes.io/control-plane' \
    2>/dev/null \
    || echo "  (could not reach cluster — verify KUBECONFIG is set)"
  echo ""
}

phase3_label_taint_backends() {
  log_phase 3 "Label and taint backend nodes (weka.io/supports-backends + weka.io/axon:NoSchedule)"

  log_info "Waiting for all nodes to reach Ready state (timeout: 300s)..."
  kubectl wait --for=condition=Ready nodes --all \
    --timeout=300s

  local -a backend_nodes=("${LABEL_BACKEND_NODES[@]}")

  log_info "Applying weka.io/supports-backends=true to: ${backend_nodes[*]}"
  kubectl label node "${backend_nodes[@]}" \
    weka.io/supports-backends=true \
    --overwrite

  log_info "Applying taint weka.io/axon=true:NoSchedule to: ${backend_nodes[*]}"
  kubectl taint nodes "${backend_nodes[@]}" \
    weka.io/axon=true:NoSchedule \
    --overwrite

  log_info "Backend node labels and taints:"
  kubectl get nodes --show-labels | grep -E "NAME|weka\.io/supports-backends"
  echo ""
  for node in "${backend_nodes[@]}"; do
    local taints
    taints=$(kubectl get node "${node}" \
      -o jsonpath='{range .spec.taints[*]}{.key}={.value}:{.effect}{"\n"}{end}' \
      2>/dev/null | grep "weka\.io" || true)
    log_info "  ${node}  taints: ${taints:-<none>}"
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  trap 'log_error "Script failed at line ${LINENO}. Exit code: $?"' ERR

  load_config
  PHASES_TO_RUN=(3)
  check_prerequisites

  if [[ $# -eq 0 || "$1" == "--help" || "$1" == "-h" ]]; then
    print_usage_backends
    exit 0
  fi

  LABEL_BACKEND_NODES=()

  case "$1" in
    --all)
      while IFS= read -r node; do
        LABEL_BACKEND_NODES+=("${node}")
      done < <(get_worker_nodes)
      if [[ ${#LABEL_BACKEND_NODES[@]} -eq 0 ]]; then
        log_error "No worker nodes found in the cluster."
        exit 1
      fi
      log_info "Targeting all ${#LABEL_BACKEND_NODES[@]} worker nodes."
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
      LABEL_BACKEND_NODES=("${all_nodes[@]:0:${n_nodes}}")
      log_info "Targeting first ${n_nodes} of ${total_nodes} worker nodes."
      ;;
    -*)
      log_error "Unknown option: $1"
      print_usage_backends
      exit 1
      ;;
    *)
      LABEL_BACKEND_NODES=("$@")
      ;;
  esac

  validate_vars
  phase3_label_taint_backends
fi
