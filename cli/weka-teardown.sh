#!/usr/bin/env bash
# weka-teardown.sh — Remove all WEKA Kubernetes resources in reverse-phase order.
# OCI infrastructure (OKE cluster, VCN, nodes) is NOT touched.
# Run 'terraform destroy' in terraform/ to remove infrastructure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=weka-lib.sh
source "${SCRIPT_DIR}/weka-lib.sh"

teardown() {
  local kc="--kubeconfig=${KUBECONFIG_FILE}"
  local to="--timeout=${TEARDOWN_TIMEOUT}"
  local namespace="default"

  echo ""
  echo "════════════════════════════════════════════════════════"
  echo "  TEARDOWN: Removing all WEKA + OKE resources"
  echo "════════════════════════════════════════════════════════"
  echo ""
  log_info "Kubeconfig   : ${KUBECONFIG_FILE}"
  log_info "Step timeout : ${TEARDOWN_TIMEOUT}  (override with TEARDOWN_TIMEOUT=<value>)"
  echo ""

  # ── Step 1: Delete reader test pod (phase 14) ─────────────────────────────────
  log_info "Step 1: Deleting reader test pod..."
  local reader_manifest="${DEPLOY_DIR}/test/weka-client-reader.yaml"
  if [[ -f "${reader_manifest}" ]]; then
    kubectl delete -f "${reader_manifest}" \
      --namespace="${namespace}" --ignore-not-found ${to} ${kc} || true
  else
    log_info "  ${reader_manifest} not found — skipping."
  fi

  # ── Step 2: Delete writer test pod (phase 14) ─────────────────────────────────
  log_info "Step 2: Deleting writer test pod..."
  local writer_manifest="${DEPLOY_DIR}/test/weka-client-writer.yaml"
  if [[ -f "${writer_manifest}" ]]; then
    kubectl delete -f "${writer_manifest}" \
      --namespace="${namespace}" --ignore-not-found ${to} ${kc} || true
  else
    log_info "  ${writer_manifest} not found — skipping."
  fi

  # ── Step 3: Delete test PVC (phase 14) ────────────────────────────────────────
  log_info "Step 3: Deleting PVC pvc-wekafs-dir..."
  kubectl delete pvc/pvc-wekafs-dir \
    --namespace="${namespace}" --ignore-not-found ${to} ${kc} || true

  # ── Step 4: Delete StorageClass (phase 14) ────────────────────────────────────
  log_info "Step 4: Deleting StorageClass..."
  local sc_manifest="${DEPLOY_DIR}/storageclass.yaml"
  if [[ -f "${sc_manifest}" ]]; then
    kubectl delete -f "${sc_manifest}" --ignore-not-found ${to} ${kc} || true
  else
    log_info "  ${sc_manifest} not found — skipping."
  fi

  # ── Step 5: Unmount wekafs from client pods (phase 13) ────────────────────────
  log_info "Step 5: Unmounting wekafs from client pods (best effort)..."
  local client_pods
  client_pods=$(kubectl get pods \
    --namespace="${namespace}" \
    --selector='weka.io/client-name' \
    --field-selector='status.phase=Running' \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
    ${kc} 2>/dev/null | grep -v '^$' || true)

  if [[ -n "${client_pods}" ]]; then
    while IFS= read -r pod; do
      log_info "  Unmounting /mnt/weka on pod: ${pod}"
      kubectl exec "${pod}" --namespace="${namespace}" ${kc} \
        -- sh -c "umount /mnt/weka 2>/dev/null || true" || true
    done <<< "${client_pods}"
  else
    log_info "  No running client pods found — skipping unmount."
  fi

#  # ── Step 6: Delete ensure-nics WekaPolicy (phase 11) ──────────────────────────
#  log_info "Step 6: Deleting ensure-nics-policy WekaPolicy..."
#  kubectl delete wekapolicy ensure-nics-policy \
#    -n weka-operator-system --ignore-not-found ${to} ${kc} || true

#  # ── Step 7: Helm uninstall csi-wekafs + delete namespace (phase 10) ───────────
#  log_info "Step 7: Uninstalling csi-wekafs Helm release..."
#  helm uninstall csi-wekafs \
#    -n "${CSI_WEKAFS_NAMESPACE}" \
#    --timeout "${TEARDOWN_TIMEOUT}" \
#    --kubeconfig "${KUBECONFIG_FILE}" 2>/dev/null \
#    || log_info "  csi-wekafs release not found — skipping."
#  kubectl delete namespace "${CSI_WEKAFS_NAMESPACE}" \
#    --ignore-not-found ${to} ${kc} || true

  # ── Step 8: Delete WekaClient CR (phase 9) ────────────────────────────────────
  log_info "Step 8: Deleting WekaClient cluster-clients..."
  kubectl delete wekaclient cluster-clients \
    -n "${namespace}" --ignore-not-found ${to} ${kc} || true

  echo "  Waiting for client pods to terminate..."
  for i in {1..60}; do
      PODS=$(kubectl get pods -n --namespace="${namespace}" -l weka.io/mode=client --no-headers 2>/dev/null | wc -l || echo "0")
      if [[ "$PODS" -eq 0 ]]; then break; fi
      sleep 5
  done

  # Force-delete stuck client resources
  REMAINING=$(kubectl get wekacontainers --namespace="${namespace}" -l weka.io/mode=client --no-headers 2>/dev/null | wc -l || echo "0")
  if [[ "$REMAINING" -gt 0 ]]; then
      echo "  Force-deleting stuck client containers..."
      kubectl get wekacontainers --namespace="${namespace}" -l weka.io/mode=client --no-headers -o name 2>/dev/null | xargs -I {} kubectl patch {} --namespace="${namespace}" -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
      kubectl delete wekacontainers -l weka.io/mode=client --namespace="${namespace}" --force --grace-period=0 2>/dev/null || true
  fi

  # ── Step 9: Patch + delete WekaCluster CR (phase 8) ───────────────────────────
  log_info "Step 9: Patching WekaCluster cluster-dev (gracefulDestroyDuration=0)..."
  kubectl patch WekaCluster cluster-dev \
    --type='merge' -p='{"spec":{"gracefulDestroyDuration": "0"}}' -n "${namespace}" ${kc} 2>/dev/null \
    || log_info "  WekaCluster cluster-dev not found — skipping patch."

  log_info "Step 9: Deleting WekaCluster cluster-dev..."
  kubectl delete wekacluster cluster-dev \
    -n "${namespace}" --ignore-not-found ${to} ${kc} || true

  echo "  Waiting for cluster pods to terminate..."
  for i in {1..120}; do
      PODS=$(kubectl get pods --namespace="${namespace}" -l app=weka --no-headers 2>/dev/null | wc -l || echo "0")
      if [[ "$PODS" -eq 0 ]]; then break; fi
      sleep 5
  done

  # Force-delete stuck cluster resources
  REMAINING=$(kubectl get wekacontainers --namespace="${namespace}" --no-headers 2>/dev/null | wc -l || echo "0")
  if [[ "$REMAINING" -gt 0 ]]; then
      echo "  Force-deleting stuck containers..."
      kubectl get wekacontainers --namespace="${namespace}" --no-headers -o name 2>/dev/null | xargs -I {} kubectl patch {} --namespace="${namespace}" -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
      kubectl delete wekacontainers --all --namespace="${namespace}" --force --grace-period=0 2>/dev/null || true
  fi  


  # ── Step 10: Delete sign-drives WekaPolicy (phase 7) ──────────────────────────
  log_info "Step 10: Deleting sign-all-drives-policy WekaPolicy..."
  kubectl delete wekapolicy sign-all-drives-policy \
    -n weka-operator-system --ignore-not-found ${to} ${kc} || true

  # ── Step 11: Helm uninstall weka-operator (phase 6) ───────────────────────────
  log_info "Step 11: Uninstalling weka-operator Helm release..."
  helm uninstall weka-operator \
    -n weka-operator-system \
    --timeout "${TEARDOWN_TIMEOUT}" \
    --kubeconfig "${KUBECONFIG_FILE}" 2>/dev/null \
    || log_info "  weka-operator release not found — skipping."

  # ── Step 12: Delete weka-operator-system namespace (phases 5+6) ───────────────
  log_info "Step 12: Deleting weka-operator-system namespace (cascades to secrets)..."
  kubectl delete namespace weka-operator-system \
    --ignore-not-found ${to} ${kc} || true

  # ── Step 13: Delete all WEKA CRDs (phase 4) ───────────────────────────────────
  log_info "Step 13: Deleting WEKA CRDs..."
  local weka_crds
  weka_crds=$(kubectl get crds ${kc} 2>/dev/null | awk 'NR>1 && /weka/ {print $1}' || true)
  if [[ -n "${weka_crds}" ]]; then
    while IFS= read -r crd; do
      log_info "  Deleting CRD: ${crd}"
      kubectl delete crd "${crd}" --ignore-not-found ${to} ${kc} || true
    done <<< "${weka_crds}"
  else
    log_info "  No WEKA CRDs found."
  fi

  # ── Step 14: Remove weka.io node labels (phase 3) ─────────────────────────────
  log_info "Step 14: Removing weka.io node labels from all nodes..."
  kubectl label nodes --all \
    weka.io/supports-backends- \
    weka.io/supports-clients- \
    ${kc} 2>/dev/null || true

  echo ""
  log_info "Teardown complete. All WEKA Kubernetes resources have been removed."
  log_info "OCI infrastructure (OKE cluster, VCN, nodes) still exists."
  log_info "Run 'terraform destroy' in the terraform/ directory to remove it."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  trap 'log_error "Script failed at line ${LINENO}. Exit code: $?"' ERR
  load_config
  check_prerequisites
  teardown
fi
