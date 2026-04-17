#!/usr/bin/env bash
# setup_ssh_config.sh
# Generate an SSH config snippet for WEKA cluster nodes and install it into
# ~/.ssh/config via an Include directive.
#
# Usage:
#   ./cli/setup_ssh_config.sh [--name <name>] [-u <user>] [--identity <key-path>]
#
# What it does:
#   1. Resolves config <name>: use --name value, or fall back to cluster_id from Terraform.
#   2. Runs get_ips_instances_prefix.sh --all-vnics and parses the
#      "# Public IPs (single line)" section to obtain one IP per Host block.
#   3. Writes deploy/ssh_config.project-weka-<name> (one Host weka<N> block per IP).
#   4. Copies the file to ~/.ssh/config.d/project-weka-<name>.
#   5. Prepends "Include ~/.ssh/config.d/project-weka-<name>" to ~/.ssh/config
#      at the top level if the line is not already present.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/../terraform"
DEPLOY_DIR="${SCRIPT_DIR}/../deploy"

# ── Defaults ──────────────────────────────────────────────────────────────────
NAME=""
SSH_USER="opc"
IDENTITY_FILE=${SSH_PRIV_KEY_PATH}

# ── Argument parsing ──────────────────────────────────────────────────────────
print_usage() {
  cat << 'EOF'
Usage: ./cli/setup_ssh_config.sh [--name <name>] [-u <user>] [--identity <key>]

Options:
  --name <name>      Base name for the SSH config file.
                     Final filename: project-weka-<name>
                     If omitted, cluster_id is read from 'terraform output'.
  -u <user>          SSH login user. Default: opc
  --identity <path>  Path to the SSH private key.
                     Default: ~/.ssh/ed25519
  --help, -h         Show this message.

Generated files:
  deploy/ssh_config.project-weka-<name>   (local staging copy)
  ~/.ssh/config.d/project-weka-<name>     (installed SSH fragment)
  ~/.ssh/config                           (Include line prepended if missing)

Example:
  ./cli/setup_ssh_config.sh --name dev -u opc
  ./cli/setup_ssh_config.sh                     # name from Terraform cluster_id
  ./cli/setup_ssh_config.sh --name dev -u ubuntu --identity ~/.ssh/id_ed25519
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)       NAME="$2";          shift 2 ;;
    --name=*)     NAME="${1#--name=}"; shift   ;;
    -u)           SSH_USER="$2";      shift 2 ;;
    -u=*)         SSH_USER="${1#-u=}"; shift   ;;
    --identity)   IDENTITY_FILE="$2"; shift 2 ;;
    --identity=*) IDENTITY_FILE="${1#--identity=}"; shift ;;
    --help|-h)    print_usage; exit 0 ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      print_usage >&2
      exit 1 ;;
  esac
done

# ── Resolve config name ───────────────────────────────────────────────────────
if [[ -z "${NAME}" ]]; then
  if ! command -v terraform &>/dev/null; then
    echo "ERROR: --name not supplied and terraform is not in PATH." >&2
    exit 1
  fi
  echo "No --name supplied — reading cluster_id from Terraform output..." >&2
  CLUSTER_ID="$(terraform -chdir="${TF_DIR}" output -raw cluster_id 2>/dev/null || true)"
  if [[ -z "${CLUSTER_ID}" ]]; then
    echo "ERROR: Could not read cluster_id from Terraform." >&2
    echo "       Run 'terraform apply' first, or pass --name <name>." >&2
    exit 1
  fi
  # OKE node display-names embed the last 11 chars of the cluster OCID unique string
    # e.g. ocid1.cluster.oc1.eu-frankfurt-1.aaaaaa...cz6spr2oqbq → cz6spr2oqbq
  NAME="${CLUSTER_ID: -11}"
  echo "Derived name from Terraform: ${NAME}" >&2
fi

CONFIG_NAME="project-weka-${NAME}"
DEPLOY_CONFIG="${DEPLOY_DIR}/ssh_config.${CONFIG_NAME}"
SSH_CONFIG_D="${HOME}/.ssh/config.d"
TARGET_CONFIG="${SSH_CONFIG_D}/${CONFIG_NAME}"
SSH_CONFIG="${HOME}/.ssh/config"
INCLUDE_LINE="Include ~/.ssh/config.d/${CONFIG_NAME}"

echo ""
echo "  Config name   : ${CONFIG_NAME}"
echo "  SSH user      : ${SSH_USER}"
echo "  Identity file : ${IDENTITY_FILE}"
echo "  Deploy file   : ${DEPLOY_CONFIG}"
echo "  Target file   : ${TARGET_CONFIG}"
echo ""

# ── Collect instance mapping ──────────────────────────────────────────────────
echo "Fetching instance mapping via get_ips_instances_prefix.sh --all-vnics ..."
echo ""

IP_OUTPUT="$("${SCRIPT_DIR}/get_ips_instances_prefix.sh" --all-vnics)"

# Parse the "# Instance mapping (instance-number:name:public-ip)" section.
# Each non-blank line after the header has the form: <num>:<display-name>:<public-ip>
# The section is already sorted by instance number (trailing integer in display-name).
INST_NUMS=()
INST_NAMES=()
INST_IPS=()

IN_MAPPING=false
while IFS= read -r line; do
  if [[ "${line}" == "# Instance mapping"* ]]; then
    IN_MAPPING=true
    continue
  fi
  if [[ "${IN_MAPPING}" == true ]]; then
    [[ -z "${line}" ]] && break          # blank line ends the section
    inst_num="${line%%:*}"               # everything before the first colon
    rest="${line#*:}"                    # everything after the first colon
    inst_name="${rest%%:*}"              # display-name (before second colon)
    pub_ip="${rest#*:}"                  # public IP (after second colon)
    [[ -n "${pub_ip}" ]] || continue
    INST_NUMS+=("${inst_num}")
    INST_NAMES+=("${inst_name}")
    INST_IPS+=("${pub_ip}")
  fi
done <<< "${IP_OUTPUT}"

NUM_HOSTS=${#INST_NUMS[@]}

if [[ "${NUM_HOSTS}" -eq 0 ]]; then
  echo "ERROR: Could not parse instance mapping from get_ips_instances_prefix.sh output." >&2
  echo ""
  echo "Raw output:" >&2
  echo "${IP_OUTPUT}" >&2
  exit 1
fi

echo "Found ${NUM_HOSTS} instance(s):"
for i in "${!INST_NUMS[@]}"; do
  echo "  weka${INST_NUMS[$i]}  →  ${INST_NAMES[$i]}  (${INST_IPS[$i]})"
done
echo ""

# ── Generate SSH config fragment ──────────────────────────────────────────────
mkdir -p "${DEPLOY_DIR}"

{
  echo "# -----------------------------------------------------------------------"
  echo "# Generated by cli/setup_ssh_config.sh on $(date)"
  echo "# Cluster : ${CONFIG_NAME}"
  echo "# Nodes   : ${NUM_HOSTS}"
  echo "# -----------------------------------------------------------------------"
  echo ""

  for i in "${!INST_NUMS[@]}"; do
    N="${INST_NUMS[$i]}"
    IP="${INST_IPS[$i]}"
    DISPLAY="${INST_NAMES[$i]}"

    echo "Host weka${N}"
    echo "    # OCI display-name: ${DISPLAY}"
    echo "    HostName ${IP}"
    echo "    User ${SSH_USER}"
    echo "    IdentityFile ${IDENTITY_FILE}"
    echo "    AddKeysToAgent no"
    echo "    UseKeychain no"
    echo "    StrictHostKeyChecking no"
    echo "    UserKnownHostsFile /dev/null"
    echo ""
  done
} > "${DEPLOY_CONFIG}"

echo "SSH config fragment written to:"
echo "  ${DEPLOY_CONFIG}"
echo ""
cat "${DEPLOY_CONFIG}"

# ── Copy to ~/.ssh/config.d/ ──────────────────────────────────────────────────
mkdir -p "${SSH_CONFIG_D}"
chmod 700 "${SSH_CONFIG_D}"
cp "${DEPLOY_CONFIG}" "${TARGET_CONFIG}"
chmod 600 "${TARGET_CONFIG}"
echo "Installed to: ${TARGET_CONFIG}"
echo ""

# ── Prepend Include to ~/.ssh/config ─────────────────────────────────────────
# The Include directive must appear before any Host / Match block to be treated
# as a top-level (global) include by OpenSSH.
if [[ ! -f "${SSH_CONFIG}" ]]; then
  echo "Creating ${SSH_CONFIG} ..."
  printf '%s\n\n' "${INCLUDE_LINE}" > "${SSH_CONFIG}"
  chmod 600 "${SSH_CONFIG}"
  echo "Created ${SSH_CONFIG} with Include directive."

elif grep -qF "${INCLUDE_LINE}" "${SSH_CONFIG}"; then
  echo "Include directive already present in ${SSH_CONFIG} — no changes needed."

else
  # Prepend: write Include line + blank line, then the existing file content
  TMP="$(mktemp)"
  {
    printf '%s\n\n' "${INCLUDE_LINE}"
    cat "${SSH_CONFIG}"
  } > "${TMP}"
  mv "${TMP}" "${SSH_CONFIG}"
  chmod 600 "${SSH_CONFIG}"
  echo "Prepended '${INCLUDE_LINE}' to ${SSH_CONFIG}"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Done. You can now connect to your WEKA nodes with:"
for i in "${!INST_NUMS[@]}"; do
  echo "  ssh weka${INST_NUMS[$i]}   # ${INST_NAMES[$i]} (${INST_IPS[$i]})"
done
echo ""
echo "To remove this config later, delete:"
echo "  ${TARGET_CONFIG}"
echo "  And the Include line from ${SSH_CONFIG}"
