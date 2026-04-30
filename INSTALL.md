# WEKA Axon on Oracle Kubernetes Engine (OKE) — Installation Guide

Deploys a WEKA Axon storage cluster on OCI OKE using the WEKA Kubernetes Operator.
Covers infrastructure provisioning, node labelling and tainting, cluster formation,
client attachment, CSI storage, and end-to-end validation with shared-filesystem
read/write test pods.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Prerequisites](#2-prerequisites)
3. [Cluster Resources](#3-cluster-resources)
   - [3.1 Recommended Node Shape — BM.DenseIO.E4.128](#31-recommended-node-shape--bmdenseioe4128)
   - [3.2 Minimum Cluster Size](#32-minimum-cluster-size)
   - [3.3 Resource Breakdown per Node](#33-resource-breakdown-per-node)
4. [Repository Layout](#4-repository-layout)
5. [Configuration](#5-configuration)
   - [5.1 OCI Credentials](#51-oci-credentials)
   - [5.2 terraform.tfvars](#52-terraformtfvars)
   - [5.3 WEKA Credentials](#53-weka-credentials)
6. [Deployment Steps](#6-deployment-steps)
7. [Manifest Reference](#7-manifest-reference)
8. [Teardown](#8-teardown)
9. [Useful Commands](#9-useful-commands)

---

## 1. Overview

```
┌──────────────────────────────────────────────────────────────────┐
│  OCI Tenancy                                                     │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  OKE Enhanced Cluster                                      │  │
│  │                                                            │  │
│  │  Backend nodes  ──►  WekaCluster CR  (Axon storage)        │  │
│  │  weka.io/supports-backends=true                            │  │
│  │  taint: weka.io/axon=true:NoSchedule                       │  │
│  │                                                            │  │
│  │  Client nodes   ──►  WekaClient CR   (workload access)     │  │
│  │  weka.io/supports-clients=true                             │  │
│  │                                                            │  │
│  │  All nodes      ──►  weka-operator + csi-wekafs            │  │
│  └────────────────────────────────────────────────────────────┘  │
│  VCN · Subnets · Security Lists · Internet/NAT Gateways          │
└──────────────────────────────────────────────────────────────────┘
```

**Key components:**

| Component | Version | Role |
|---|---|---|
| WEKA Operator | `v1.11.0` | Manages cluster lifecycle via Kubernetes CRs |
| csi-wekafs | bundled with operator | StorageClass / PVC provisioner |
| WekaCluster CR | — | Defines the Axon storage cluster (backend nodes, drives, containers) |
| WekaClient CR | — | Attaches client nodes to the cluster |
| OKE Module | `oracle-terraform-modules/oke/oci v5.4.2` | OCI infrastructure (VCN, cluster, node pool) |

---

## 2. Prerequisites

### Tools

Install via `cli/utils/install-tools.sh` (Ubuntu) or manually:

```bash
sudo cli/utils/install-tools.sh --all   # installs terraform, jq, oci-cli
```

| Tool | Min version | Purpose |
|---|---|---|
| `terraform` | 1.14.7 | OCI infrastructure provisioning |
| `kubectl` | 1.27+ | Kubernetes cluster management |
| `helm` | 3.x | WEKA operator and CSI installation |
| `jq` | any | JSON parsing in scripts |
| `oci` CLI | latest | OKE kubeconfig generation |

### OCI Access

- An OCI tenancy with sufficient quota for bare metal or DenseIO VM instances
- A user with IAM policies to manage OKE clusters, VCNs, and compute instances
- An API key pair configured in `~/.oci/config`

Verify the CLI is working before starting:

```bash
oci iam region list
```

### WEKA Access

Contact the **WEKA Customer Success Team** before starting. You will need:

- `QUAY_USERNAME` and `QUAY_PASSWORD` — quay.io robot credentials for image pull
- WEKA operator version (`WEKA_OPERATOR_VERSION`)
- WEKA container image tag (`WEKA_IMAGE`)

---

## 3. Cluster Resources

### 3.1 Recommended Node Shape — BM.DenseIO.E4.128

The OCI **BM.DenseIO.E4.128** bare metal shape is the recommended node type for WEKA
Axon backend nodes. It provides dedicated NVMe SSDs with no virtualisation overhead,
equivalent in purpose to high-storage bare metal instances on other clouds.

| Attribute | BM.DenseIO.E4.128 |
|---|---|
| OCPUs | 128 |
| RAM | 2,048 GB |
| NVMe SSDs | 8 × 6.4 TB |
| Raw NVMe capacity | **51.2 TB per node** |
| Network | 2 × 100 Gbps (200 Gbps aggregate) |
| Architecture | x86-64 (amd64) |

Set this shape in `terraform/terraform.tfvars`:

```hcl
instance_shape = "BM.DenseIO.E4.128"
```

Other supported shapes (use for dev/test environments):

| Shape | OCPUs | RAM | NVMe | Notes |
|---|---|---|---|---|
| `VM.DenseIO.E4.Flex` | up to 32 | up to 512 GB | 1–4 × 6.4 TB | VM, flexible sizing |
| `VM.DenseIO.E5.Flex` | up to 94 | up to 1,049 GB | 1–4 × 6.4 TB | VM, newer generation |
| `BM.DenseIO.E4.128` | 128 | 2,048 GB | 8 × 6.4 TB | **Recommended for production** |

> **NVMe access:** On bare metal shapes, NVMe drives are exposed directly to the
> OS as `/dev/nvme*` block devices. The WEKA operator claims and formats them via the
> `sign-drives` WekaPolicy (Phase 7).

### 3.2 Minimum Cluster Size

WEKA requires a minimum of **6 backend nodes** for a production Axon cluster
(to satisfy the protection scheme and stripe width). This deployment defaults to 7
worker nodes to provide one additional node for client workloads.

| Role | Minimum nodes | `terraform.tfvars` |
|---|---|---|
| Backend (storage) | 6 | `worker_pool_size >= 7` |
| Client (compute) | 1+ | labelled separately after cluster formation |

For a pure-backend cluster where all nodes serve both storage and application traffic,
all 7 nodes may be labelled as backends; the WekaClient CR handles the mount-only
attachment.

### 3.3 Resource Breakdown per Node (BM.DenseIO.E4.128)

The `deploy/weka-cluster.yaml` example targets the following per-node allocation:

| Resource | Value | Notes |
|---|---|---|
| Drive containers | 1 per node (6 total) | `driveContainers: 6`, `driveCores: 2` |
| Compute containers | 1 per node (6 total) | `computeContainers: 6`, `computeCores: 2` |
| NVMe drives claimed | 1 per drive container | `numDrives: 1` (full-drives mode) |
| Hugepages per compute | 6,144 MiB | `computeCores × 3072` |
| UDP networking | enabled | `udpMode: true` |
| Base port | 15000 | `portRange: 500` |

---

## 4. Repository Layout

```
.
├── cli/
│   ├── weka-lib.sh                       # Shared utilities and variable defaults
│   ├── weka-phase1-terraform.sh          # Step  1 — OKE infrastructure
│   ├── weka-phase2-kubeconfig.sh         # Step  2 — kubeconfig extraction
│   ├── 3-weka-label-taint-backends.sh    # Step  3 — label + taint backend nodes
│   ├── 4-weka-label-clients.sh           # Step  4 — label client nodes
│   ├── 5-weka-namespaces-secrets.sh      # Step  5 — namespaces + pull secrets
│   ├── 6-weka-operator.sh                # Step  6 — Helm install operator + CSI
│   ├── 7-weka-sign-drives.sh             # Step  7 — sign-drives WekaPolicy
│   ├── 8-weka-create-cluster.sh          # Step  8 — WekaCluster CR
│   ├── 9-weka-client.sh                  # Step  9 — WekaClient CR
│   ├── 10-weka-get-credentials.sh        # Step 10 — admin credentials + UI URLs
│   ├── 12-mount-wekafs.sh                # Step 12 — mount wekafs on a client pod
│   ├── 13-test-storage-on-app-pods.sh    # Step 13 — StorageClass, PVC, writer/reader pods
│   ├── weka-teardown.sh                  # Reverse-order teardown
│   ├── weka-generate-commands.sh         # Preview all kubectl/helm commands (steps 4-9)
│   └── utils/
│       └── install-tools.sh              # Install terraform / jq / oci-cli on Ubuntu
├── terraform/
│   ├── variables.tf                      # All input variables
│   ├── locals.tf                         # Shape/image/version resolution logic
│   ├── modules.tf                        # OKE module call
│   ├── data.tf                           # OCI data sources
│   ├── outputs.tf                        # cluster_id, kubeconfig, endpoints
│   ├── terraform.tfvars.example          # Template — copy and populate
│   └── user-data/
│       ├── managed_OL_OKE.yaml           # Cloud-init for Oracle Linux OKE nodes
│       └── managed_ubuntu.yaml           # Cloud-init for Ubuntu OKE nodes
└── deploy/                               # Generated manifests + runtime config
    ├── weka-cluster.yaml                 # WekaCluster CR  (edit before step 8)
    ├── weka-client.yaml                  # WekaClient CR   (edit before step 9)
    ├── sign-drives.yaml                  # sign-drives WekaPolicy (edit before step 7)
    ├── storageclass.yaml                 # WEKA CSI StorageClass  (edit before step 13)
    ├── cloud-init.cmd                    # Standalone equivalent of managed_OL_OKE cloud-init
    └── test/
        ├── pvc.yaml
        ├── weka-client-writer.yaml
        └── weka-client-reader.yaml
```

---

## 5. Configuration

### 5.1 OCI Credentials

The OCI CLI must be configured before Terraform can authenticate. The default config
file is `~/.oci/config`. Set `OCI_CLI_PROFILE` if you use a non-`DEFAULT` profile:

```bash
export OCI_CLI_PROFILE="myprofile"
```

### 5.2 terraform.tfvars

Copy the example file and fill in your values:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

**Required variables:**

| Variable | Example value | Description |
|---|---|---|
| `tenancy_ocid` | `ocid1.tenancy.oc1..aaa…` | OCI Tenancy OCID |
| `user_ocid` | `ocid1.user.oc1..aaa…` | OCI User OCID |
| `fingerprint` | `aa:bb:cc:…` | API key fingerprint |
| `private_key_path` | `~/.oci/oci_api_key.pem` | Path to OCI API private key |
| `region` | `eu-frankfurt-1` | OCI region identifier |
| `compartment_ocid` | `ocid1.compartment.oc1..aaa…` | Target compartment OCID |
| `ssh_public_key_path` | `~/.ssh/id_ed25519.pub` | SSH public key for node access |
| `worker_pool_size` | `7` | Number of worker nodes (minimum 7) |
| `instance_shape` | `BM.DenseIO.E4.128` | Node shape (see [Section 3.1](#31-recommended-node-shape--bmdenseioe4128)) |

**Node image — choose one:**

| Scenario | Variables to set |
|---|---|
| Oracle Linux (default) | `ol_managed_nodes = true` |
| Ubuntu 24.04 (Noble) | `ubuntu_managed_nodes = true`, `ubuntu_release = "noble"` |
| Ubuntu 22.04 (Jammy) | `ubuntu_managed_nodes = true`, `ubuntu_release = "jammy"` |
| Custom image OCID | `image_id = "ocid1.image.oc1.."` (ignores `ubuntu_release`) |

**Optional overrides:**

```hcl
kubernetes_version = "v1.32.1"   # OKE control plane version
cni_type           = "npn"       # "npn" (recommended) or "flannel"
public_nodes       = false       # expose worker nodes on public subnet
```

### 5.3 WEKA Credentials

Export Quay.io pull secret credentials before running steps 5 onward:

```bash
export QUAY_USERNAME="weka.io+your_robot_account"
export QUAY_PASSWORD="your_robot_token"
```

Override WEKA image versions if required (defaults are set in `cli/weka-lib.sh`):

```bash
export WEKA_OPERATOR_VERSION="v1.11.0"
export WEKA_IMAGE="quay.io/weka.io/weka-in-container:5.1.0.605"
```

---

## 6. Deployment Steps

Set `KUBECONFIG` once after step 2 and all subsequent `kubectl`/`helm` calls will use it
automatically — no `--kubeconfig` flag needed.

---

### Step 1 — OCI OKE Infrastructure

Provisions the OKE Enhanced cluster, VCN, subnets, gateways, and managed node pool.

```bash
cli/weka-phase1-terraform.sh
# or directly:
cd terraform && terraform init && terraform apply
```

---

### Step 2 — Extract Kubeconfig

Pulls the kubeconfig from Terraform output and writes it to `deploy/kubeconfig`.
Exports `KUBECONFIG` for the current shell.

```bash
cli/weka-phase2-kubeconfig.sh
```

Activate in your shell (required before all subsequent steps):

```bash
source deploy/env.sh
# or:
export KUBECONFIG=$(pwd)/deploy/kubeconfig
```

Verify cluster access:

```bash
kubectl get nodes
```

---

### Step 3 — Label and Taint Backend Nodes

Labels backend nodes with `weka.io/supports-backends=true` and applies the
`weka.io/axon=true:NoSchedule` taint so that only WEKA containers are scheduled
on storage nodes.

```bash
# Show available nodes and exit:
cli/3-weka-label-taint-backends.sh --help

# Label + taint all worker nodes as backends:
cli/3-weka-label-taint-backends.sh --all

# Label + taint the first N nodes:
cli/3-weka-label-taint-backends.sh --first 6

# Label + taint specific nodes by name:
cli/3-weka-label-taint-backends.sh <node1> <node2> ...
```

Verify:

```bash
kubectl get nodes --show-labels | grep supports-backends
kubectl get nodes -o json | jq '.items[].spec.taints'
```

---

### Step 4 — Label Client Nodes

Labels client nodes with `weka.io/supports-clients=true`. These nodes will run the
WekaClient pods that mount the WEKA filesystem for application workloads.

```bash
# Show current backend and non-backend nodes:
cli/4-weka-label-clients.sh --help

# Label all remaining nodes as clients:
cli/4-weka-label-clients.sh --all

# Or label specific nodes:
cli/4-weka-label-clients.sh <node6> <node7>
```

---

### Step 5 — Namespaces and Pull Secrets

Creates the `weka-operator-system` namespace and the `quay-io-robot-secret` image pull
secret in both `weka-operator-system` and `default` namespaces.

Requires `QUAY_USERNAME` and `QUAY_PASSWORD` to be set (see [Section 5.3](#53-weka-credentials)).

```bash
cli/5-weka-namespaces-secrets.sh
```

---

### Step 6 — Helm Install WEKA Operator (+ CSI)

Installs the WEKA operator from the OCI Helm registry. The CSI plugin is enabled
inline (`csi.installationEnabled=true`). Waits for the
`weka-operator-controller-manager` deployment to reach `Ready`.

```bash
cli/6-weka-operator.sh
```

Verify:

```bash
kubectl get pods -n weka-operator-system
```

---

### Step 7 — Sign Drives (WekaPolicy)

Applies the `sign-all-drives-policy` WekaPolicy so the operator claims and formats
NVMe drives on backend nodes. Review `deploy/sign-drives.yaml` before running:

```yaml
apiVersion: weka.weka.io/v1alpha1
kind: WekaPolicy
metadata:
  name: sign-all-drives-policy
  namespace: weka-operator-system
spec:
  type: "sign-drives"
  payload:
    signDrivesPayload:
      type: all-not-root
      nodeSelector:
        weka.io/supports-backends: "true"
      options:
        allowNonEmptyDevice: true
        allowEraseNonWekaPartitions: true
    interval: 5m
```

> **Warning:** `allowEraseNonWekaPartitions: true` allows the operator to erase
> existing data on NVMe partitions. Confirm drives are empty before proceeding.

```bash
cli/7-weka-sign-drives.sh

# Dry-run (generates manifest, skips kubectl apply):
cli/7-weka-sign-drives.sh -d
```

Monitor drive signing:

```bash
kubectl get wekapolicy sign-all-drives-policy -n weka-operator-system -w
```

---

### Step 8 — Deploy WekaCluster CR

Creates the Axon storage cluster on the tainted backend nodes. Review and adjust
`deploy/weka-cluster.yaml` before running:

```yaml
apiVersion: weka.weka.io/v1alpha1
kind: WekaCluster
metadata:
  name: cluster-dev
  namespace: default
spec:
  template: dynamic
  dynamicTemplate:
    computeContainers: 6      # total compute containers (1 per backend node)
    computeCores: 2           # cores per compute container
    computeHugepages: 6144    # MiB per compute container (computeCores × 3072)
    driveContainers: 6        # total drive containers (1 per backend node)
    driveCores: 2             # cores per drive container
    numDrives: 1              # NVMe drives per drive container
  image: quay.io/weka.io/weka-in-container:5.1.0.605
  imagePullSecret: "quay-io-robot-secret"
  nodeSelector:
    weka.io/supports-backends: "true"
  rawTolerations:
    - key: "weka.io/axon"
      operator: "Equal"
      value: "true"
      effect: "NoSchedule"
  csiConfig:
    advanced:
      nodeTolerations:
        - key: "weka.io/axon"
          operator: "Exists"
          effect: "NoSchedule"
      controllerTolerations:
        - key: "weka.io/axon"
          operator: "Exists"
          effect: "NoSchedule"
  driversDistService: https://drivers.weka.io
  gracefulDestroyDuration: "0"
  ports:
    basePort: 15000
    portRange: 500
  network:
    udpMode: true
```

> **Tolerations:** The `rawTolerations` block allows WEKA pods to be scheduled on
> nodes with the `weka.io/axon=true:NoSchedule` taint applied in step 3.

```bash
cli/8-weka-create-cluster.sh
```

Monitor cluster formation (can take 10–20 minutes):

```bash
kubectl get wekacluster cluster-dev -n default -w
kubectl get pods -n default -w
```

The cluster is ready when `WekaCluster` status shows `Ready`.

---

### Step 9 — Deploy WekaClient CR

Attaches client nodes to the cluster. Client pods mount the WEKA filesystem and make
it available for application workloads. Review `deploy/weka-client.yaml`:

```yaml
apiVersion: weka.weka.io/v1alpha1
kind: WekaClient
metadata:
  name: cluster-dev-clients
  namespace: default
spec:
  image: quay.io/weka.io/weka-in-container:5.1.0.605
  imagePullSecret: "quay-io-robot-secret"
  driversDistService: "https://drivers.weka.io"
  coresNum: 1
  cpuPolicy: dedicated
  cpuRequest: "500m"
  portRange:
    basePort: 46000
    portRange: 0
  nodeSelector:
    weka.io/supports-clients: "true"
  wekaSecretRef: weka-client-cluster-dev
  targetCluster:
    name: cluster-dev
    namespace: default
  upgradePolicy:
    type: all-at-once
```

```bash
cli/9-weka-client.sh
```

---

### Step 10 — Get Admin Credentials and UI Access

Retrieves the admin username and password from the cluster Kubernetes secret and
prints WEKA management UI access URLs.

```bash
cli/10-weka-get-credentials.sh
```

Example output:

```
  ┌─ WEKA Admin Credentials ────────────────────────────────────────────
  │  Username : admin
  │  Password : <decoded-password>
  └─────────────────────────────────────────────────────────────────────

  ┌─ WEKA UI Access ─────────────────────────────────────────────────────
  │  LoadBalancer detected:
  │    https://<LB_PUBLIC_IP>:15000/ui
  │
  │  kubectl port-forward svc/cluster-dev-management-proxy 8080:15245
  │    http://localhost:8080/ui
  └─────────────────────────────────────────────────────────────────────
```

---

### Step 12 — Mount wekafs on a Client Pod

Mounts the default WEKA filesystem at `/mnt/weka` inside a running client pod.

```bash
# Auto-select the first Running client pod:
cli/12-mount-wekafs.sh

# Target a specific pod by name:
cli/12-mount-wekafs.sh <pod-name>
```

Verify the mount:

```bash
kubectl exec <pod-name> -- df -h /mnt/weka
```

---

### Step 13 — StorageClass, PVC, and Test Pods

Validates end-to-end CSI storage by creating a PVC backed by `storageclass-wekafs-dir-api`
and running writer and reader pods that share the same volume.

Review `deploy/storageclass.yaml` (provisioner name must match your cluster name):

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: storageclass-wekafs-dir-api
provisioner: cluster-dev.default.weka.io
allowVolumeExpansion: true
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
parameters:
  volumeType: dir/v1
  filesystemName: default
  capacityEnforcement: HARD
  csi.storage.k8s.io/provisioner-secret-name: &secretName weka-csi-cluster-dev
  csi.storage.k8s.io/provisioner-secret-namespace: &secretNamespace default
  # ... (additional CSI secret references)
```

```bash
cli/13-test-storage-on-app-pods.sh
```

Sequence:
1. Applies `StorageClass`
2. Applies PVC → waits for `Bound` (60 s timeout)
3. Applies writer pod → waits for `Ready` (120 s timeout)
4. Applies reader pod → waits for `Ready` (60 s timeout)
5. Prints logs from both pods to confirm data was written and read

---

## 7. Manifest Reference

All manifest files live under `deploy/`. Prepare them before running the corresponding
step. Sample manifests are provided; adjust container counts, core counts, and port
ranges to match your shape and use case.

| File | Step | Key fields to review |
|---|---|---|
| `deploy/sign-drives.yaml` | 7 | `allowEraseNonWekaPartitions`, `nodeSelector` |
| `deploy/weka-cluster.yaml` | 8 | `computeContainers`, `driveContainers`, `numDrives`, `image` |
| `deploy/weka-client.yaml` | 9 | `coresNum`, `targetCluster.name`, `image` |
| `deploy/storageclass.yaml` | 13 | `provisioner` (must match cluster name), `filesystemName` |
| `deploy/test/pvc.yaml` | 13 | `storageClassName`, size |
| `deploy/test/weka-client-writer.yaml` | 13 | pod image, volume mount path |
| `deploy/test/weka-client-reader.yaml` | 13 | pod image, volume mount path |

---

## 8. Teardown

Removes all Kubernetes resources in reverse-phase order. OCI infrastructure is
**not** destroyed automatically — run `terraform destroy` separately.

```bash
# Default timeout (120 s per step):
cli/weka-teardown.sh

# Shorter timeout:
TEARDOWN_TIMEOUT=60s cli/weka-teardown.sh
```

Then destroy the OCI infrastructure:

```bash
cd terraform && terraform destroy
```

---

## 9. Useful Commands

```bash
# Watch cluster formation
kubectl get wekacluster cluster-dev -n default -w

# Watch all WEKA pods
kubectl get pods -n default -w

# Check operator logs
kubectl logs -n weka-operator-system deploy/weka-operator-controller-manager -f

# List all WEKA custom resources
kubectl get wekacluster,wekaclient,wekapolicy -A

# Verify filesystem mount inside a client pod
kubectl exec <pod-name> -- df -h /mnt/weka

# Preview all kubectl/helm commands for steps 4–9 with values substituted
cli/weka-generate-commands.sh

# Run cloud-init script manually on a node via SSH
scp -F deploy/ssh_config.<cluster> deploy/cloud-init.cmd <node>:/tmp/cloud-init.cmd
ssh -F deploy/ssh_config.<cluster> <node> "sudo bash /tmp/cloud-init.cmd"

# Tail cloud-init log on a node
ssh -F deploy/ssh_config.<cluster> <node> "sudo tail -f /var/log/oke-node-init.log"
```
