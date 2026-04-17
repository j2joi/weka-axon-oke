#!/usr/bin/env bash
# Phase 12: Get WEKA cluster admin credentials and UI access info
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=weka-lib.sh
source "${SCRIPT_DIR}/weka-lib.sh"

phase12_get_credentials() {
  log_phase 12 "Get WEKA cluster admin credentials"

  local secret="weka-cluster-cluster-dev"
  local namespace="default"

  # ── Credentials ───────────────────────────────────────────────────────────────
  log_info "Fetching credentials from secret: ${secret}"

  local username password
  username=$(kubectl get "secrets/${secret}" \
    --namespace="${namespace}" \
    --template='{{.data.username}}' \
    | base64_decode)

  password=$(kubectl get "secrets/${secret}" \
    --namespace="${namespace}" \
    --template='{{.data.password}}' \
    | base64_decode)

  echo ""
  echo "  ┌─ WEKA Admin Credentials ────────────────────────────────────────────"
  echo "  │  Username : ${username}"
  echo "  │  Password : ${password}"
  echo "  └─────────────────────────────────────────────────────────────────────"
  echo ""

  # ── LoadBalancer IP (if any) ──────────────────────────────────────────────────
  local lb_ip
  lb_ip=$(kubectl get svc \
    --namespace="${namespace}" \
    --field-selector='spec.type=LoadBalancer' \
    -o jsonpath='{.items[*].status.loadBalancer.ingress[0].ip}' \
    2>/dev/null | xargs)

  # ── Worker node external IPs ──────────────────────────────────────────────────
  local node_ips
  node_ips=$(kubectl get nodes \
    --selector='!node-role.kubernetes.io/control-plane,weka.io/supports-backends' \
    -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="ExternalIP")].address}{"\n"}{end}' \
    2>/dev/null | grep -v '^$' || true)

  # ── Access instructions ───────────────────────────────────────────────────────
  echo "  ┌─ WEKA UI Access ─────────────────────────────────────────────────────"

  if [[ -n "${lb_ip}" ]]; then
    echo "  │"
    echo "  │  LoadBalancer detected:"
    for ip in ${lb_ip}; do
      echo "  │    https://${ip}:15000/ui"
    done
  else
    echo "  │  No LoadBalancer found in namespace '${namespace}'."
    echo "  │  If one is provisioned later: https://<LB_PUBLIC_IP>:15000/ui"
  fi

  if [[ -n "${node_ips}" ]]; then
    echo "  │"
    echo "  │  Worker node public IPs (if nodes are publicly accessible):"
    while IFS= read -r ip; do
      echo "  │    https://${ip}:15000/ui"
    done <<< "${node_ips}"
  else
    echo "  │"
    echo "  │  No worker node external IPs found."
    echo "  │  If nodes are public: https://<NODES_PUBLIC_IP>:15000/ui"
  fi
    echo "  │"
    echo "  │"
    echo "  │"
    echo "  │  Also, you could use Proxy Service to access console:  "
    echo "  │ - Find proxy pod and then do a port-forward from your browser on port 8080 to the port below.  "
    echo "  │  \$ kubectl get svc | grep proxy  "
    echo "  │      cluster-dev-management-proxy   ClusterIP   10.96.184.167   <none>        15245/TCP"
    echo "  │  kubectl port-forward svc/cluster-dev-management-proxy 8080:15245 "
    echo "  │  "
    echo "  │  Access locally in a web browser at:"
    echo "  │      http://localhost:8080/ui"
    echo "  └─────────────────────────────────────────────────────────────────────"
  echo ""
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  trap 'log_error "Script failed at line ${LINENO}. Exit code: $?"' ERR
  load_config
  PHASES_TO_RUN=(12)
  check_prerequisites
  validate_vars
  phase12_get_credentials
fi
