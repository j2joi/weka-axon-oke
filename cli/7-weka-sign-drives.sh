#!/usr/bin/env bash
# Phase 7: Sign Drives (generate sign-drives WekaPolicy manifest)
#
# Usage (standalone): ./7-weka-sign-drives.sh [-d]
#   -d   Dry-run: generate YAML manifest but skip kubectl apply.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=weka-lib.sh
source "${SCRIPT_DIR}/weka-lib.sh"

phase7_sign_drives() {
  log_phase 7 "Sign Drives — generating sign-drives WekaPolicy manifest"

  mkdir -p "${DEPLOY_DIR}"
  local manifest="${DEPLOY_DIR}/sign-drives.yaml"

  log_info "Applying sign-drives WekaPolicy..."
  kubectl_apply "${manifest}"
  [[ "${DRY_RUN}" == "true" ]] && return

  log_info "sign-drives WekaPolicy applied. Current status:"
  kubectl get wekapolicy sign-all-drives-policy \
    -n weka-operator-system \
    2>/dev/null || true
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
  PHASES_TO_RUN=(7)
  check_prerequisites
  validate_vars
  phase7_sign_drives
fi
