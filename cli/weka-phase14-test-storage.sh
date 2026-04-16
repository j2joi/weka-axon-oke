#!/usr/bin/env bash
# Phase 14: Apply StorageClass, PVC, and test writer/reader pods
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=weka-lib.sh
source "${SCRIPT_DIR}/weka-lib.sh"

phase14_test_storage() {
  log_phase 14 "Apply StorageClass, PVC, and test writer/reader pods"

  local namespace="default"
  local kc="--kubeconfig=${KUBECONFIG_FILE}"

  local storageclass_manifest="${DEPLOY_DIR}/storageclass.yaml"
  local pvc_manifest="${DEPLOY_DIR}/test/pvc.yaml"
  local writer_manifest="${DEPLOY_DIR}/test/weka-client-writer.yaml"
  local reader_manifest="${DEPLOY_DIR}/test/weka-client-reader.yaml"

  # ── Validate manifests exist ──────────────────────────────────────────────────
  local missing=0
  for f in "${storageclass_manifest}" "${pvc_manifest}" "${writer_manifest}" "${reader_manifest}"; do
    if [[ ! -f "${f}" ]]; then
      log_error "Manifest not found: ${f}"
      (( missing++ )) || true
    fi
  done
  [[ ${missing} -gt 0 ]] && exit 1

  # ── StorageClass (cluster-scoped) ─────────────────────────────────────────────
  log_info "Applying StorageClass: ${storageclass_manifest}"
  kubectl apply -f "${storageclass_manifest}" ${kc}

  # ── PVC ───────────────────────────────────────────────────────────────────────
  log_info "Applying PVC: ${pvc_manifest}"
  kubectl apply -f "${pvc_manifest}" --namespace="${namespace}" ${kc}

    # ── Writer pod ────────────────────────────────────────────────────────────────
  log_info "Applying writer pod: ${writer_manifest}"
  local writer_resource
  writer_resource=$(kubectl apply -f "${writer_manifest}" \
    --namespace="${namespace}" \
    --output=name \
    ${kc})
  log_info "Created: ${writer_resource}"

  log_info "Waiting for writer pod to be Ready (timeout: 60s)..."
  kubectl wait "${writer_resource}" \
    --namespace="${namespace}" \
    --for=condition=Ready \
    --timeout=120s \
    ${kc}
 # ── PVC Ready ? ───────────────────────────────────────────────────────────────────────
  log_info "Waiting for PVC pvc-wekafs-dir to be Bound (timeout: 60s)..."
  kubectl wait pvc/pvc-wekafs-dir \
    --namespace="${namespace}" \
    --for=jsonpath='{.status.phase}'=Bound \
    --timeout=60s \
    ${kc}

  local pvc_phase
  pvc_phase=$(kubectl get pvc pvc-wekafs-dir \
    --namespace="${namespace}" \
    -o jsonpath='{.status.phase}' \
    ${kc})
  log_info "PVC status: ${pvc_phase}"

  # ── Reader pod ────────────────────────────────────────────────────────────────
  log_info "Applying reader pod: ${reader_manifest}"
  local reader_resource
  reader_resource=$(kubectl apply -f "${reader_manifest}" \
    --namespace="${namespace}" \
    --output=name \
    ${kc})
  log_info "Created: ${reader_resource}"

  log_info "Waiting for reader pod to be Ready (timeout: 60s)..."
  kubectl wait "${reader_resource}" \
    --namespace="${namespace}" \
    --for=condition=Ready \
    --timeout=60s \
    ${kc}

  log_info "Storage test complete. Writer and reader pods are Ready."
  echo ""
  kubectl get pvc,pods \
    --namespace="${namespace}" \
    ${kc} | grep -E "NAME|pvc-wekafs-dir|$(basename "${writer_resource}")|$(basename "${reader_resource}")"
  echo ""

  # ── Confirm Mounted and Shared ────────────────────────────────────────────────────────────────
  echo ""
  echo "Test Results:"
  echo ""
  echo "Writer:"
  kubectl logs weka-oke-app-writer --namespace="${namespace}" 2>/dev/null || echo "  (not ready yet)"
  echo ""
  echo "Reader:"
  kubectl logs weka-oke-app-reader --namespace="${namespace}" 2>/dev/null || echo "  (not ready yet)"

}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  trap 'log_error "Script failed at line ${LINENO}. Exit code: $?"' ERR
  load_config
  check_prerequisites
  PHASES_TO_RUN=(14)
  validate_vars
  phase14_test_storage
fi
