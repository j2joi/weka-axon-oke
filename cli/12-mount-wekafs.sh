#!/usr/bin/env bash
# Phase 13: Mount wekafs filesystem on a client pod
#
# Usage (standalone): ./12-mount-wekafs.sh [pod-name]
#   pod-name   Mount on this specific pod (must be Running).
#   (no args)  Auto-select the first Running pod labeled weka.io/supports-clients=true.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=weka-lib.sh
source "${SCRIPT_DIR}/weka-lib.sh"

phase13_mount_wekafs() {
  log_phase 13 "Mount wekafs on client pod"

  local namespace="default"
  local target_pod=""

  # ── Resolve target pod ────────────────────────────────────────────────────────
  if [[ -n "${TARGET_POD:-}" ]]; then
    # Pod name supplied explicitly — validate it exists and is Running
    log_info "Pod specified: ${TARGET_POD}"
    local phase
    phase=$(kubectl get pod "${TARGET_POD}" \
      --namespace="${namespace}" \
      -o jsonpath='{.status.phase}' \
      2>/dev/null || true)

    if [[ -z "${phase}" ]]; then
      log_error "Pod '${TARGET_POD}' not found in namespace '${namespace}'."
      exit 1
    fi
    if [[ "${phase}" != "Running" ]]; then
      log_error "Pod '${TARGET_POD}' is not Running (current phase: ${phase})."
      exit 1
    fi
    target_pod="${TARGET_POD}"

  else
    # Auto-discover: first Running pod with label weka.io/supports-clients=true
    log_info "No pod specified — looking for Running pods with label weka.io/supports-clients=true..."

    local running_pods
    running_pods=$(kubectl get pods \
      --namespace="${namespace}" \
      --selector='weka.io/client-name' \
      --field-selector='status.phase=Running' \
      -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
      2>/dev/null | grep -v '^$' || true)

    if [[ -z "${running_pods}" ]]; then
      log_error "No Running pods with label weka.io/supports-clients=true found in namespace '${namespace}'."
      echo ""
      echo "  Label at least one pod and confirm it is in Running state."
      echo ""
      exit 1
    fi

    target_pod=$(echo "${running_pods}" | head -1)

    log_info "Found pods:"
    while IFS= read -r pod; do
      if [[ "${pod}" == "${target_pod}" ]]; then
        log_info "  ${pod}  ← selected"
      else
        log_info "  ${pod}"
      fi
    done <<< "${running_pods}"
  fi

  # ── Mount wekafs ──────────────────────────────────────────────────────────────
  log_info "Mounting wekafs on pod: ${target_pod}"
  kubectl exec "${target_pod}" \
    --namespace="${namespace}" \
    -- sh -c "mkdir -p /mnt/weka && mount -t wekafs default /mnt/weka/"

  log_info "Mount complete. Verifying..."
  kubectl exec "${target_pod}" \
    --namespace="${namespace}" \
    -- sh -c "df -h /mnt/weka"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  trap 'log_error "Script failed at line ${LINENO}. Exit code: $?"' ERR

  TARGET_POD=""

  case "${1:-}" in
    --help|-h)
      echo "Usage: $0 [pod-name]"
      echo ""
      echo "  pod-name   Mount wekafs on this specific pod (must be Running)."
      echo "  (no args)  Auto-select the first Running pod labeled weka.io/supports-clients=true."
      exit 0
      ;;
    "")
      ;;
    -*)
      log_error "Unknown argument: $1"
      exit 1
      ;;
    *)
      TARGET_POD="$1"
      ;;
  esac

  load_config
  PHASES_TO_RUN=(13)
  check_prerequisites
  validate_vars
  phase13_mount_wekafs
fi
