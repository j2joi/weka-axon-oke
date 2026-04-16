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
├── weka-deploy.env         # Your credentials (gitignored, copy from example)
├── cli/
│   ├── weka-lib.sh                       # Shared utilities and defaults
│   ├── weka-deploy.env.example           # Credential template
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

Copy the example env file and fill in your values:

```bash
cp cli/weka-deploy.env.example weka-deploy.env
```

**Required variables:**

```bash
# OCI authentication — choose one:
OCI_CONFIG_FILE="$HOME/.oci/config"   # Option A: OCI config file (recommended)
OCI_CONFIG_PROFILE="DEFAULT"

# Option B: explicit credentials (only if not using OCI_CONFIG_FILE)
# TENANCY_OCID="ocid1.tenancy.oc1.."
# USER_OCID="ocid1.user.oc1.."
# FINGERPRINT="xx:xx:xx:xx"
# PRIVATE_KEY_PATH="$HOME/.oci/oci_api_key.pem"
# REGION="us-ashburn-1"

# Infrastructure
COMPARTMENT_OCID="ocid1.compartment.oc1.."
SSH_PUBLIC_KEY_PATH="$HOME/.ssh/id_rsa.pub"
SSH_PRIVATE_KEY_PATH="$HOME/.ssh/id_rsa"
IMAGE_ID="ocid1.image.oc1.."   # Ubuntu OKE worker image

# WEKA registry (provided by WEKA support)
QUAY_USERNAME="weka-robot+your_account"
QUAY_PASSWORD="your_quay_password"
```

**Optional overrides** (defaults shown):

```bash
WEKA_IMAGE="quay.io/weka.io/weka-in-container:5.1.0.605"
WEKA_OPERATOR_VERSION="v1.11.0"
DATA_NICS_NUMBER=2
KUBECONFIG_FILE="./deploy/kubeconfig"
```

---

## Step-by-Step Deployment

### Phase 1 — OCI OKE Infrastructure

Provisions the OKE cluster, VCN, subnets, gateways, and managed node pool via Terraform.
Workspace defaults to `dev`. Override with `TF_WORKSPACE=<name>`.

```bash
cli/weka-phase1-terraform.sh
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
