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

  terraform plan -var-file="${SCRIPT_DIR}/../terraform/terraform.tfvars"

  log_info "Running terraform apply"
#  terraform apply -auto-approve -var "ol_managed_nodes=false" "${tf_vars[@]}"
  terraform apply  -var-file="${SCRIPT_DIR}/../terraform/terraform.tfvars" -var "ol_managed_nodes=false" -auto-approve

  log_info "Terraform apply complete."
  log_info "Cluster ID: $(terraform output -raw cluster_id)"

  cd "${PROJECT_ROOT}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  trap 'log_error "Script failed at line ${LINENO}. Exit code: $?"' ERR
#  load_config
#  check_prerequisites
#  PHASES_TO_RUN=(1)
#  validate_vars
  phase1_terraform
fi
