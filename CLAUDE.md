# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This project provides IaC for deploying Oracle Kubernetes Engine (OKE) clusters on OCI, with two parallel deployment approaches: a Bash CLI approach and a Terraform approach.

## Development Environment

Tool versions are managed via `.mise.toml` (Terraform 1.14.7). OCI credentials and paths are configured there as environment variables:

```bash
mise install   # installs terraform and sets up python venv
```

Key env vars set by `.mise.toml`:
- `TF_VAR_tenancy_id` — OCI tenancy OCID
- `OCI_CLI_PROFILE` — OCI CLI profile (default: `ASH`)
- `SSH_PUB_KEY_PATH` — path to SSH public key

## Deployment: CLI Approach (`cli/`)

Run scripts in order after configuring `cli/env.sh`:

```bash
source cli/env.sh
./cli/setup_networking.sh       # creates VCN, gateways, subnets, security lists
./cli/create_cluster.sh         # creates OKE enhanced cluster + kubeconfig
./cli/create_managed_nodes.sh   # creates OKE-managed node pool
# OR
./cli/create_self_managed_nodes.sh   # creates self-managed VM instances
```

Prerequisites: `oci` CLI, `kubectl`, `jq`.

## Deployment: Terraform Approach (`terraform/`)

```bash
cd terraform/
terraform init
terraform plan
terraform apply
terraform destroy
```

Copy `terraform.tfvars.example` to `terraform.tfvars` and populate with real OCIDs before running.

## Terraform Architecture

The Terraform code uses the `oracle-terraform-modules/oke/oci` module (v5.4.2). Key files:

- **`variables.tf`** — all inputs; required: `tenancy_ocid`, `user_ocid`, `fingerprint`, `private_key_path`, `region`, `compartment_ocid`, `ssh_public_key_path`, `ssh_private_key_path`, `image_id`
- **`locals.tf`** — complex logic: architecture→shape mapping, Kubernetes version parsing, OKE package selection, conditional node pool creation
- **`modules.tf`** — OKE module call; creates VCN, subnets (cp, int_lb, pub_lb, workers, pods, bastion, operator), security groups, cluster
- **`data.tf`** — OCI data sources
- **`outputs.tf`** — cluster_id, kubeconfig, endpoints

### Key Terraform Variables

| Variable | Default | Notes |
|---|---|---|
| `kubernetes_version` | `v1.32.1` | Validated against known versions |
| `cni_type` | `flannel` | `flannel` or `npn` |
| `architecture` | `amd64` | `amd64` → E5.Flex, `arm64` → A1.Flex |
| `ubuntu_release` | `jammy` | `jammy` or `noble` |
| `add_managed_nodes` | `true` | Toggle managed node pool |
| `add_self_managed_nodes` | `false` | Toggle self-managed nodes |
| `public_nodes` | `false` | Place nodes on public subnet |

### Cloud-Init / User-Data (`terraform/user-data/`)

Templates for bootstrapping nodes. Self-managed nodes use `ubuntu-self-managed.yaml` which installs OKE packages matching the Kubernetes version and runs `oke bootstrap` to join the cluster. Managed nodes use variants per OS (Oracle Linux or Ubuntu).

## Networking

- Pod CIDR: `10.244.0.0/16`
- Services CIDR: `10.96.0.0/16`
- Cluster type is always `enhanced` (required for self-managed node support)
