#!/usr/bin/env bash
# Phase 1: Terraform init + apply (OCI OKE infrastructure)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=weka-lib.sh
source "${SCRIPT_DIR}/weka-lib.sh"

phase1_terraform() {
  log_phase 1 "Terraform init + apply (OCI OKE infrastructure)"

  if [[ ! -d "${TF_DIR}" ]]; then
    log_error "Terraform directory not found: ${TF_DIR}"
    exit 1
  fi

  cd "${TF_DIR}"

  log_info "Running terraform init"
  terraform init

  local tf_vars=(
    -var "compartment_ocid=${COMPARTMENT_OCID}"
    -var "ssh_public_key_path=${SSH_PUBLIC_KEY_PATH}"
    -var "ssh_private_key_path=${SSH_PRIVATE_KEY_PATH}"
    -var "image_id=${IMAGE_ID}"
    -var "add_managed_nodes=true"
  )

  if [[ -z "${OCI_CONFIG_FILE:-}" ]]; then
    tf_vars+=(
      -var "tenancy_ocid=${TENANCY_OCID}"
      -var "user_ocid=${USER_OCID}"
      -var "fingerprint=${FINGERPRINT}"
      -var "private_key_path=${PRIVATE_KEY_PATH}"
      -var "region=${REGION}"
    )
  else
    log_info "OCI_CONFIG_FILE is set — provider will read credentials from: ${OCI_CONFIG_FILE}"
    export OCI_CONFIG_FILE="${OCI_CONFIG_FILE/#\~/$HOME}"
  fi

  log_info "Running terraform apply"
  terraform apply -auto-approve "${tf_vars[@]}"

  log_info "Terraform apply complete."
  log_info "Cluster ID: $(terraform output -raw cluster_id)"

  cd "${PROJECT_ROOT}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  trap 'log_error "Script failed at line ${LINENO}. Exit code: $?"' ERR
  load_config
  check_prerequisites
  PHASES_TO_RUN=(1)
  validate_vars
  phase1_terraform
fi
