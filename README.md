# WEKA Axon on Oracle Kubernetes Engine (OKE)

Deploys a WEKA Axon cluster on OCI OKE using the WEKA Kubernetes Operator. Covers
infrastructure provisioning, cluster formation, client attachment, CSI storage, and
end-to-end validation with shared-filesystem read/write test pods.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  OCI Tenancy                                                │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  OKE Cluster (Enhanced)                             │   │
│  │                                                     │   │
│  │  Backend nodes  ──►  WekaCluster CR                 │   │
│  │  (weka.io/supports-backends=true)    (Axon cluster) │   │
│  │                                                     │   │
│  │  Client nodes   ──►  WekaClient CR                  │   │
│  │  (weka.io/supports-clients=true)     (UDP or DPDK)  │   │
│  │                                                     │   │
│  │  All nodes      ──►  weka-operator + CSI plugin     │   │
│  └─────────────────────────────────────────────────────┘   │
│  VCN · Subnets · Security Lists · Internet/NAT Gateways    │
└─────────────────────────────────────────────────────────────┘
```

**Key components:**
- **WEKA Operator** (`v1.11.0`) — manages cluster lifecycle via Kubernetes CRs; ships with the CSI plugin (`csi.installationEnabled=true`)
- **WekaCluster CR** — defines the Axon storage cluster (backend nodes, drives, containers)
- **WekaClient CR** — attaches client nodes to the cluster
- **csi-wekafs** — provides `StorageClass` / PVC support for Kubernetes workloads

---

## Prerequisites

| Tool | Purpose |
|---|---|
| `terraform` >= 1.14 | OCI infrastructure provisioning |
| `kubectl` | Kubernetes cluster management |
| `helm` >= 3 | WEKA operator and CSI installation |
| `jq` | JSON parsing in scripts |
| `oci` CLI | (optional) image and compartment discovery |

OCI access requires either an `~/.oci/config` file or explicit API credentials. See
[Configuration](#configuration) below.

---

## Repository Layout

```
.
├── cli/
│   ├── weka-lib.sh                       # Shared utilities and defaults
│   ├── weka-phase1-terraform.sh          # Phase  1 — OKE infrastructure
│   ├── weka-phase2-kubeconfig.sh         # Phase  2 — kubeconfig extraction
│   ├── weka-phase3-label-backends.sh     # Phase  3 — label backend nodes
│   ├── weka-phase3-label-clients.sh      # Phase  3 — label client nodes
│   ├── weka-phase4-install-crds.sh       # Phase  4 — WEKA operator CRDs
│   ├── weka-phase5-namespaces-secrets.sh # Phase  5 — namespaces + pull secrets
│   ├── weka-phase6-helm-operator.sh      # Phase  6 — Helm install operator + CSI
│   ├── weka-phase7-sign-drives.sh        # Phase  7 — sign-drives WekaPolicy
│   ├── weka-phase8-create-cluster.sh     # Phase  8 — WekaCluster CR
│   ├── weka-phase9-weka-client.sh        # Phase  9 — WekaClient CR
│   ├── weka-phase12-get-credentials.sh   # Phase 12 — admin credentials + UI URLs
│   ├── weka-phase13-mount-wekafs.sh      # Phase 13 — mount wekafs on a client pod
│   ├── weka-phase14-test-storage.sh      # Phase 14 — StorageClass, PVC, writer/reader pods
│   └── weka-teardown.sh                 # Reverse-order teardown
├── terraform/              # OKE cluster + VCN Terraform module
└── deploy/                 # Generated manifests + kubeconfig (gitignored)
    ├── storageclass.yaml
    ├── weka-cluster.yaml   # WekaCluster CR (prepare before phase 8)
    ├── weka-client.yaml    # WekaClient CR  (prepare before phase 9)
    ├── sign-drives.yaml    # sign-drives WekaPolicy (prepare before phase 7)
    └── test/
        ├── pvc.yaml
        ├── weka-client-writer.yaml
        └── weka-client-reader.yaml
```

---

## Configuration

### OCI CLI

A working [OCI CLI](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm)
installation is required. The CLI is used by Phase 2 to authenticate against the OKE
control plane and generate the kubeconfig. Verify it is configured correctly before
starting:

```bash
oci iam region list   # should return a list of OCI regions without error
```

The CLI reads credentials from `~/.oci/config` by default. Set `OCI_CONFIG_PROFILE` if
you use a non-`DEFAULT` profile.

### terraform/terraform.tfvars

Copy the example and fill in your values:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

**Required variables:**

| Variable | Description |
|---|---|
| `tenancy_ocid` | OCI Tenancy OCID |
| `user_ocid` | OCI User OCID |
| `fingerprint` | API key fingerprint |
| `private_key_path` | Path to the OCI API private key (`.pem`) |
| `region` | OCI region (e.g. `eu-frankfurt-1`) |
| `compartment_ocid` | Target compartment OCID |
| `ssh_public_key_path` | SSH public key path for worker node access |
| `worker_pool_size` | Number of worker nodes (minimum `7`) |
| `instance_shape` | Worker node shape (see `variables.tf` for supported values) |

**Node image — choose one:**

| Scenario | Variables to set |
|---|---|
| Oracle Linux (default) | `ol_managed_nodes = true` |
| Ubuntu Noble | `ubuntu_managed_nodes = true`, `ubuntu_release = "noble"` |
| Ubuntu Jammy | `ubuntu_managed_nodes = true`, `ubuntu_release = "jammy"` |
| Custom image OCID | `image_id = "ocid1.image.oc1.."` |

> **Note:** VM flex shapes are only compatible with Oracle Linux OKE images.
> Bare metal shapes support both Oracle Linux and Ubuntu.

**Optional overrides** (defaults shown):

```hcl
kubernetes_version = "v1.33.1"
cni_type           = "npn"      # "npn" or "flannel"
public_nodes       = false
```

### WEKA Credentials

Contact the **WEKA Customer Success Team** to obtain the necessary setup information
before starting the deployment. You will need:

**Container repository (quay.io) — image pull secrets:**

| Variable | Description |
|---|---|
| `QUAY_USERNAME` | quay.io robot account username (e.g. `weka.io+example_user`) |
| `QUAY_PASSWORD` | quay.io robot account password |

These are required by Phase 5 to create the `quay-io-robot-secret` image pull secret.
Export them in your shell before running the scripts:

```bash
export QUAY_USERNAME="example_user"
export QUAY_PASSWORD="example_password"
```

**WEKA operator and image versions:**

For the most current versions refer to the
[WEKA Operator page](https://get.weka.io/ui/operator).

```bash
WEKA_OPERATOR_VERSION="v1.11.0"
WEKA_IMAGE="quay.io/weka.io/weka-in-container:5.1.0.605"
```

Gathering this information in advance provides all the required values to complete
the deployment workflow efficiently.

---

## Step-by-Step Deployment

### Phase 1 — OCI OKE Infrastructure

Provisions the OKE cluster, VCN, subnets, gateways, and managed node pool via Terraform.
The Terraform code is built on the
[Oracle OKE Terraform Module](https://registry.terraform.io/modules/oracle-terraform-modules/oke/oci/latest)
(`oracle-terraform-modules/oke/oci` v5.4.2).

Run via the phase script:

```bash
cli/weka-phase1-terraform.sh
```

Or run Terraform directly:

```bash
cd terraform/
terraform init
terraform apply
```

---

### Phase 2 — Extract Kubeconfig

Pulls the kubeconfig from Terraform output and writes it to `deploy/kubeconfig`.

```bash
cli/weka-phase2-kubeconfig.sh
```

Activate in your shell:

```bash
source deploy/env.sh
# or:
export KUBECONFIG=./deploy/kubeconfig
```

---

### Phase 3 — Label Worker Nodes

Label nodes to designate which ones act as WEKA **backends** (storage) and which as
**clients** (compute workloads).

Run each script with no arguments to print the current node list and usage, then
pass node names explicitly:

```bash
# Show available nodes and exit:
cli/weka-phase3-label-backends.sh

# Label specific nodes as backends (storage cluster nodes):
cli/weka-phase3-label-backends.sh node1 node2 node3
```

```bash
# Show non-backend nodes and exit:
cli/weka-phase3-label-clients.sh

# Label remaining nodes as clients (workload nodes):
cli/weka-phase3-label-clients.sh node4 node5
```

> Backend nodes host WEKA drive and compute containers.
> Client nodes mount the filesystem and run application pods.

---

### Phase 4 — Install WEKA Operator CRDs

Installs the Custom Resource Definitions required before the operator is deployed.

```bash
cli/weka-phase4-install-crds.sh
```

---

### Phase 5 — Namespaces and Pull Secrets

Creates the `weka-operator-system` namespace and the `quay-io-robot-secret` image pull
secret in both `weka-operator-system` and `default` namespaces.
Requires `QUAY_USERNAME` and `QUAY_PASSWORD`.

```bash
cli/weka-phase5-namespaces-secrets.sh
```

---

### Phase 6 — Helm Install WEKA Operator (+ CSI)

Installs the WEKA operator from the OCI Helm registry. The CSI plugin is enabled
inline (`csi.installationEnabled=true`). Waits for the
`weka-operator-controller-manager` deployment to be fully ready.

```bash
cli/weka-phase6-helm-operator.sh
```

---

### Phase 7 — Sign Drives (WekaPolicy)

Applies the `sign-drives` WekaPolicy so the operator can claim and format drives on
backend nodes.

Prepare `deploy/sign-drives.yaml` before running. Example:

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
        allowEraseNonWekaPartitions: true
    interval: 5m
```

```bash
cli/weka-phase7-sign-drives.sh

# Dry-run — apply manifest without kubectl apply:
cli/weka-phase7-sign-drives.sh -d
```

---

### Phase 8 — Deploy WekaCluster CR

Creates the Axon storage cluster on the backend nodes.

Prepare `deploy/weka-cluster.yaml` before running. Example:

```yaml
apiVersion: weka.weka.io/v1alpha1
kind: WekaCluster
metadata:
  name: cluster-dev
  namespace: default
spec:
  template: dynamic
  dynamicTemplate:
    computeContainers: 6
    driveContainers: 6
    computeCores: 2
    driveCores: 1
    numDrives: 1
  image: quay.io/weka.io/weka-in-container:5.1.0.605
  nodeSelector:
    weka.io/supports-backends: "true"
  driversDistService: https://drivers.weka.io
  imagePullSecret: "quay-io-robot-secret"
  ports:
    basePort: 15000
    portRange: 500
  network:
    udpMode: true
```

```bash
cli/weka-phase8-create-cluster.sh
```

Monitor cluster formation:

```bash
kubectl get wekacluster cluster-dev -n default -w
kubectl get pods -n default -w
```

---

### Phase 9 — Deploy WekaClient CR

Attaches client nodes to the cluster. Client pods mount the WEKA filesystem
and make it available for application workloads.

Prepare `deploy/weka-client.yaml` before running. Example:

```yaml
apiVersion: weka.weka.io/v1alpha1
kind: WekaClient
metadata:
  name: cluster-clients
  namespace: default
spec:
  image: quay.io/weka.io/weka-in-container:5.1.0.605
  imagePullSecret: "quay-io-robot-secret"
  driversDistService: "https://drivers.weka.io"
  portRange:
    basePort: 46000
  nodeSelector:
    weka.io/supports-clients: "true"
  wekaSecretRef: weka-client-cluster-dev
  targetCluster:
    name: cluster-dev
    namespace: default
```

```bash
cli/weka-phase9-weka-client.sh
```

---

### Phase 12 — Get Admin Credentials and UI Access

Retrieves the admin username and password from the cluster secret and prints
the WEKA management UI URLs.

```bash
cli/weka-phase12-get-credentials.sh
```

Output example:

```
  ┌─ WEKA Admin Credentials ────────────────────────────────────────────
  │  Username : admin
  │  Password : <decoded>
  └─────────────────────────────────────────────────────────────────────

  ┌─ WEKA UI Access ─────────────────────────────────────────────────────
  │  LoadBalancer detected:
  │    https://1.2.3.4:15000/ui
  │  Worker node public IPs:
  │    https://10.0.0.5:15000/ui
  └─────────────────────────────────────────────────────────────────────
```

---

### Phase 13 — Mount wekafs on a Client Pod

Mounts the default WEKA filesystem at `/mnt/weka` inside a running client pod.
If no matching pod is found the script prints the current pod list and exits.

```bash
# Auto-select the first Running client pod:
cli/weka-phase13-mount-wekafs.sh

# Or target a specific pod:
cli/weka-phase13-mount-wekafs.sh <pod-name>
```

---

### Phase 14 — StorageClass, PVC, and Test Writer/Reader Pods

Validates end-to-end shared filesystem access by creating a PVC backed by the WEKA
CSI driver and running two pods that write and read from the same volume.

Prepare the following manifests before running:

| File | Resource |
|---|---|
| `deploy/storageclass.yaml` | WEKA CSI `StorageClass` |
| `deploy/test/pvc.yaml` | `PersistentVolumeClaim` named `pvc-wekafs-dir` |
| `deploy/test/weka-client-writer.yaml` | Pod that writes to the PVC |
| `deploy/test/weka-client-reader.yaml` | Pod that reads from the PVC |

```bash
cli/weka-phase14-test-storage.sh
```

Sequence:
1. Apply `StorageClass`
2. Apply PVC → wait for `Bound` (60 s timeout)
3. Apply writer pod → wait for `Ready` (120 s timeout)
4. Apply reader pod → wait for `Ready` (60 s timeout)
5. Print logs from both pods to confirm data was written and read

---

## Teardown

Removes all Kubernetes resources in reverse-phase order. OCI infrastructure is **not**
destroyed — run `terraform destroy` separately to remove it.

```bash
# With default timeout (120s per step):
cli/weka-teardown.sh

# With a shorter timeout:
TEARDOWN_TIMEOUT=60s cli/weka-teardown.sh
```

Teardown order:

| Step | Action |
|---|---|
| 1 | Delete reader test pod |
| 2 | Delete writer test pod |
| 3 | Delete PVC `pvc-wekafs-dir` |
| 4 | Delete StorageClass |
| 5 | Unmount `/mnt/weka` from all running client pods |
| 6 | Delete `ensure-nics-policy` WekaPolicy |
| 7 | Helm uninstall `csi-wekafs` + delete namespace |
| 8 | Delete WekaClient `cluster-clients` (waits for termination, force-deletes stuck containers) |
| 9 | Patch + delete WekaCluster `cluster-dev` (waits for termination, force-deletes stuck containers) |
| 10 | Delete `sign-all-drives-policy` WekaPolicy |
| 11 | Helm uninstall `weka-operator` |
| 12 | Delete `weka-operator-system` namespace (cascades secrets) |
| 13 | Delete all WEKA CRDs |
| 14 | Remove `weka.io` node labels |

Every step uses `--ignore-not-found` or `|| true` — missing resources are skipped.

---

## Useful Commands

```bash
# Watch cluster formation
kubectl get wekacluster cluster-dev -n default -w

# Watch all WEKA pods
kubectl get pods -n default -w

# Check operator logs
kubectl logs -n weka-operator-system deploy/weka-operator-controller-manager -f

# Check CSI driver pods
kubectl get pods -n weka-operator-system

# Verify filesystem mount inside a client pod
kubectl exec <pod> -- df -h /mnt/weka

# List all WEKA custom resources
kubectl get wekacluster,wekaclient,wekapolicy -A
```
