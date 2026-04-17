#!/usr/bin/env bash
# Install terraform, jq, and/or OCI CLI on Ubuntu.
#
# Usage:
#   ./install-tools.sh --all                 Install all three tools
#   ./install-tools.sh terraform             Install Terraform only
#   ./install-tools.sh jq                    Install jq only
#   ./install-tools.sh oci                   Install OCI CLI only
#   ./install-tools.sh terraform jq          Install multiple specific tools
set -euo pipefail

# ── Versions ──────────────────────────────────────────────────────────────────
TERRAFORM_VERSION="1.14.7"

# ── Helpers ───────────────────────────────────────────────────────────────────
log_info()  { echo "[INFO]  $(date '+%H:%M:%S') $*"; }
log_error() { echo "[ERROR] $(date '+%H:%M:%S') $*" >&2; }

require_ubuntu() {
  if ! grep -qi ubuntu /etc/os-release 2>/dev/null; then
    log_error "This script targets Ubuntu. Detected OS:"
    grep PRETTY_NAME /etc/os-release 2>/dev/null || echo "  (unknown)"
    exit 1
  fi
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    log_error "Run as root or with sudo: sudo $0 $*"
    exit 1
  fi
}

already_installed() {
  local tool="$1"
  if command -v "${tool}" &>/dev/null; then
    log_info "${tool} already installed: $(command -v "${tool}") — $(${tool} --version 2>&1 | head -1)"
    return 0
  fi
  return 1
}

# ── Installers ────────────────────────────────────────────────────────────────
install_terraform() {
  log_info "Installing Terraform ${TERRAFORM_VERSION}..."

  if already_installed terraform; then
    local current
    current=$(terraform version -json 2>/dev/null | grep -o '"[0-9][^"]*"' | head -1 | tr -d '"' || terraform version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [[ "${current}" == "${TERRAFORM_VERSION}" ]]; then
      log_info "Already at requested version ${TERRAFORM_VERSION} — skipping."
      return 0
    fi
    log_info "Installed version (${current}) differs from requested (${TERRAFORM_VERSION}) — reinstalling."
  fi

  apt-get install -y gnupg software-properties-common wget

  wget -qO /usr/share/keyrings/hashicorp-archive-keyring.gpg \
    https://apt.releases.hashicorp.com/gpg

  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    > /etc/apt/sources.list.d/hashicorp.list

  apt-get update -y
  apt-get install -y "terraform=${TERRAFORM_VERSION}-*"

  log_info "Terraform installed: $(terraform version | head -1)"
}

install_jq() {
  log_info "Installing jq..."

  if already_installed jq; then
    return 0
  fi

  apt-get update -y
  apt-get install -y jq

  log_info "jq installed: $(jq --version)"
}

install_oci() {
  log_info "Installing OCI CLI..."

  if already_installed oci; then
    return 0
  fi

  # Prerequisites
  apt-get update -y
  apt-get install -y python3 python3-pip python3-venv curl

  # Oracle-provided installer; --accept-all-defaults runs non-interactively
  # and installs into ~/lib/oracle-cli with shell rc integration.
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)" \
    -- --accept-all-defaults

  # Reload PATH so oci is visible in the current shell
  OCI_BIN="${HOME}/bin/oci"
  if [[ -x "${OCI_BIN}" ]]; then
    export PATH="${HOME}/bin:${PATH}"
    log_info "OCI CLI installed: $(oci --version)"
  else
    log_info "OCI CLI installed. Open a new shell or run: source ~/.bashrc"
  fi
}

# ── Usage ─────────────────────────────────────────────────────────────────────
print_usage() {
  echo ""
  echo "Usage: $0 [--all | tool [tool ...]]"
  echo ""
  echo "Tools:"
  echo "  terraform   Install Terraform ${TERRAFORM_VERSION}"
  echo "  jq          Install jq (latest via apt)"
  echo "  oci         Install OCI CLI (latest via Oracle installer)"
  echo ""
  echo "Examples:"
  echo "  sudo $0 --all"
  echo "  sudo $0 terraform"
  echo "  sudo $0 jq oci"
  echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
if [[ $# -eq 0 || "$1" == "--help" || "$1" == "-h" ]]; then
  print_usage
  exit 0
fi

require_ubuntu
require_root "$@"

declare -A to_install=()

for arg in "$@"; do
  case "${arg}" in
    --all)
      to_install[terraform]=1
      to_install[jq]=1
      to_install[oci]=1
      ;;
    terraform|jq|oci)
      to_install["${arg}"]=1
      ;;
    *)
      log_error "Unknown tool: '${arg}'. Valid options: --all, terraform, jq, oci"
      print_usage
      exit 1
      ;;
  esac
done

[[ -n "${to_install[terraform]:-}" ]] && install_terraform
[[ -n "${to_install[jq]:-}"        ]] && install_jq
[[ -n "${to_install[oci]:-}"       ]] && install_oci

log_info "Done."
