#!/usr/bin/env bash
# weka-lib.sh — Shared utilities for WEKA OKE deploy phase scripts
#
# Source this file from each phase script; do not execute directly.

# ── Path resolution ────────────────────────────────────────────────────────────
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${LIB_DIR}/.." && pwd)"
TF_DIR="${PROJECT_ROOT}/terraform"
DEPLOY_DIR="${PROJECT_ROOT}/deploy"
# ── Defaults (overridable via environment variables) ──────────────────────────
: "${WEKA_IMAGE:=quay.io/weka.io/weka-in-container:5.1.0.605}"
: "${WEKA_OPERATOR_VERSION:=v1.11.0}"
: "${DATA_NICS_NUMBER:=2}"
: "${CORES_NUM:=4}"
: "${BASE_PORT:=46000}"
: "${TF_WORKSPACE:=dev}"
: "${TEARDOWN_TIMEOUT:=120s}"
: "${CSI_WEKAFS_NAMESPACE:=csi-wekafs}"
: "${DRY_RUN:=false}"

# ── Logging ────────────────────────────────────────────────────────────────────
log_info()  { echo "[INFO]  $(date '+%H:%M:%S') $*"; }
log_error() { echo "[ERROR] $(date '+%H:%M:%S') $*" >&2; }
log_phase() {
  echo ""
  echo "════════════════════════════════════════════"
  echo "  Phase $1: $2"
  echo "════════════════════════════════════════════"
  echo ""
}

# ── Configuration loading ──────────────────────────────────────────────────────
load_config() {
  log_info "Loading config"
#  if [[ -f "${CONFIG_FILE}" ]]; then
#    log_info "Loading config from ${CONFIG_FILE}"
#    # shellcheck source=/dev/null
#    set -a; source "${CONFIG_FILE}"; set +a
#  fi
}

# ── Prerequisite check ─────────────────────────────────────────────────────────
# Requires PHASES_TO_RUN to be set before calling.
# terraform is only needed for phases 1 (apply) and 2 (output).
check_prerequisites() {
  local missing=()
  local tools=(kubectl helm)

  local p
  for p in "${PHASES_TO_RUN[@]}"; do
    if [[ "${p}" == "1" || "${p}" == "2" ]]; then
      tools+=(terraform)
      break
    fi
  done

  for tool in "${tools[@]}"; do
    if ! command -v "${tool}" &>/dev/null; then
      missing+=("${tool}")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "Missing required tools: ${missing[*]}"
    log_error "Install them and retry."
    exit 1
  fi
  log_info "Prerequisites OK: ${tools[*]}"
}

# ── OCI config file parser ─────────────────────────────────────────────────────
# If OCI_CONFIG_FILE is set, parse the INI profile and backfill any OCI API
# vars not already set in the environment. Explicit values always win.
parse_oci_config() {
  local config_file="${OCI_CONFIG_FILE/#\~/$HOME}"
  local profile="${OCI_CONFIG_PROFILE:-DEFAULT}"

  if [[ ! -f "${config_file}" ]]; then
    log_error "OCI_CONFIG_FILE points to a non-existent file: ${config_file}"
    exit 1
  fi

  log_info "Reading OCI credentials from ${config_file} [${profile}]"

  local in_profile=false
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%%#*}"
    line="${line%"${line##*[![:space:]]}"}"

    if [[ "${line}" =~ ^\[([^\]]+)\]$ ]]; then
      [[ "${BASH_REMATCH[1]}" == "${profile}" ]] && in_profile=true || in_profile=false
      continue
    fi

    "${in_profile}" || continue
    [[ "${line}" =~ ^([^=[:space:]]+)[[:space:]]*=[[:space:]]*(.+)$ ]] || continue

    local key="${BASH_REMATCH[1]}"
    local val="${BASH_REMATCH[2]}"

    case "${key}" in
      tenancy)     [[ -z "${TENANCY_OCID:-}"    ]] && export TENANCY_OCID="${val}"    ;;
      user)        [[ -z "${USER_OCID:-}"        ]] && export USER_OCID="${val}"        ;;
      fingerprint) [[ -z "${FINGERPRINT:-}"      ]] && export FINGERPRINT="${val}"      ;;
      key_file)    [[ -z "${PRIVATE_KEY_PATH:-}" ]] && export PRIVATE_KEY_PATH="${val/#\~/$HOME}" ;;
      region)      [[ -z "${REGION:-}"           ]] && export REGION="${val}"           ;;
    esac
  done < "${config_file}"
}

# ── Variable validation ────────────────────────────────────────────────────────
# Validates only variables required by the phases listed in PHASES_TO_RUN.
validate_vars() {
  local errors=0

  needs_phase() { local p; for p in "${PHASES_TO_RUN[@]}"; do [[ "${p}" == "$1" ]] && return 0; done; return 1; }

  if needs_phase 1; then
    if [[ -n "${OCI_CONFIG_FILE:-}" ]]; then
      parse_oci_config
      log_info "OCI_CONFIG_FILE in use — skipping manual OCI API credential check."
    else
      for var in TENANCY_OCID USER_OCID FINGERPRINT PRIVATE_KEY_PATH REGION; do
        if [[ -z "${!var:-}" ]]; then
          log_error "Required variable not set: ${var}"
          (( errors++ )) || true
        fi
      done
    fi
    for var in COMPARTMENT_OCID SSH_PUBLIC_KEY_PATH; do
      if [[ -z "${!var:-}" ]]; then
        log_error "Required variable not set: ${var}"
        (( errors++ )) || true
      fi
    done
  fi

  if needs_phase 5; then
    for var in QUAY_USERNAME QUAY_PASSWORD; do
      if [[ -z "${!var:-}" ]]; then
        log_error "Required variable not set: ${var}"
        (( errors++ )) || true
      fi
    done
  fi

#  if needs_phase 9; then
#    if [[ -z "${WEKA_JOIN_IPS:-}" ]]; then
#      log_error "Required variable not set: WEKA_JOIN_IPS"
#      (( errors++ )) || true
#    fi
#    for var in CORES_NUM BASE_PORT; do
#      if ! [[ "${!var}" =~ ^[0-9]+$ ]]; then
#        log_error "${var} must be a positive integer, got: '${!var}'"
#        (( errors++ )) || true
#      fi
#    done
#  fi

  if [[ ${errors} -gt 0 ]]; then
    log_error "Fix the ${errors} missing/invalid variable(s) above and retry."
    log_error "Export the required variables in your shell before running the script."
    exit 1
  fi
}

# ── Dry-run kubectl apply helper ───────────────────────────────────────────────
kubectl_apply() {
  local manifest="$1"
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] Skipping kubectl apply. Manifest written to: ${manifest}"
  else
    kubectl apply -f "${manifest}"
  fi
}

# ── Cross-platform base64 decode ───────────────────────────────────────────────
base64_decode() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    base64 -D
  else
    base64 -d
  fi
}

# ── Build YAML list from comma-separated ip:port entries ──────────────────────
# Input:  "10.0.0.5:14000,10.0.0.6:14000"
# Output: ["10.0.0.5:14000","10.0.0.6:14000"]
join_ips_to_yaml_list() {
  local ips="$1"
  local result='['
  local first=true
  IFS=',' read -ra ip_list <<< "${ips}"
  for ip in "${ip_list[@]}"; do
    ip="$(echo "${ip}" | xargs)"
    if [[ "${first}" == "true" ]]; then
      result+="\"${ip}\""
      first=false
    else
      result+=",\"${ip}\""
    fi
  done
  result+=']'
  echo "${result}"
}
