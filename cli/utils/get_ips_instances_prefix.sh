
#!/usr/bin/env bash
# get_ips_instances_prefix.sh
# Lists public/private IPs for all running OCI instances whose display-name
# contains a cluster short-ID prefix.
#
# Usage:
#   ./get_ips_instances_prefix.sh [--prefix <short-id>] [--output <file>] [--all-vnics]
#   ./get_ips_instances_prefix.sh --k8s [--output <file>]
#
# If --prefix is not supplied (OCI mode), the script derives it automatically
# from the Terraform output cluster_id (last 11 characters of the OCID).
# With --k8s, node IPs are sourced directly from kubectl (no OCI calls needed).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/../terraform"

PREFIX=""
OUTPUT=""
ALL_VNICS=false
K8S_MODE=false

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix|-p)  PREFIX="$2"; shift 2 ;;
    --prefix=*)   PREFIX="${1#--prefix=}"; shift ;;
    --output|-o)  OUTPUT="$2"; shift 2 ;;
    --output=*)   OUTPUT="${1#--output=}"; shift ;;
    --all-vnics)  ALL_VNICS=true; shift ;;
    --k8s)        K8S_MODE=true; shift ;;
    --help|-h)
      echo "Usage: $0 [--prefix <short-id>] [--output <file>] [--all-vnics]"
      echo "       $0 --k8s [--output <file>]"
      echo ""
      echo "OCI mode (default):"
      echo "  --prefix     Cluster short-ID to filter instance display-names."
      echo "               If omitted, derived from 'terraform output cluster_id'."
      echo "  --all-vnics  Include all VNICs per instance (default: primary VNIC only)."
      echo ""
      echo "Kubernetes mode:"
      echo "  --k8s        Source node IPs from kubectl instead of OCI API."
      echo "               Queries worker nodes (excludes control-plane)."
      echo ""
      echo "Common:"
      echo "  --output     Write CSV output to this file (default: stdout)."
      exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# ── Output helper ─────────────────────────────────────────────────────────────
run() {
  if [[ -n "${OUTPUT}" ]]; then
    tee "${OUTPUT}"
  else
    cat
  fi
}

# ── Kubernetes mode ───────────────────────────────────────────────────────────
if [[ "${K8S_MODE}" == true ]]; then
  if ! command -v kubectl &>/dev/null; then
    echo "ERROR: kubectl not found in PATH." >&2
    exit 1
  fi

  echo "Sourcing node IPs from kubectl (worker nodes only)..." >&2

  NODE_IPS="$(kubectl get nodes \
    --selector='!node-role.kubernetes.io/control-plane' \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')"

  if [[ -z "${NODE_IPS}" ]]; then
    echo "No worker nodes found via kubectl." >&2
    exit 0
  fi

  {
    private_list=()
    while IFS= read -r ip; do
      [[ -z "${ip}" ]] && continue
      private_list+=("${ip}")
    done <<< "${NODE_IPS}"

    echo "# IPs"
    for ip in "${private_list[@]}"; do
      echo "${ip}"
    done
    echo ""
    echo "# Private IPs (comma-separated)"
    ( IFS=','; echo "${private_list[*]}" )
  } | run

  exit 0
fi

# ── OCI mode ──────────────────────────────────────────────────────────────────

# Derive prefix from Terraform if not supplied
if [[ -z "${PREFIX}" ]]; then
  if ! command -v terraform &>/dev/null; then
    echo "ERROR: --prefix not supplied and terraform is not in PATH." >&2
    exit 1
  fi
  echo "No --prefix supplied — reading cluster_id from Terraform output..." >&2
  CLUSTER_ID="$(terraform -chdir="${TF_DIR}" output -raw cluster_id 2>/dev/null)"
  if [[ -z "${CLUSTER_ID}" ]]; then
    echo "ERROR: Could not read cluster_id from Terraform. Run 'terraform apply' first or pass --prefix." >&2
    exit 1
  fi
  # OKE node display-names embed the last 11 chars of the cluster OCID unique string
  # e.g. ocid1.cluster.oc1.eu-frankfurt-1.aaaaaa...cz6spr2oqbq → cz6spr2oqbq
  PREFIX="${CLUSTER_ID: -11}"
  echo "Derived prefix: ${PREFIX}" >&2
fi

echo "Filtering instances with display-name containing: ${PREFIX}" >&2

# ── Fetch and format ──────────────────────────────────────────────────────────
oci compute instance list \
    --all \
    --query "data[?contains(\"display-name\", \`${PREFIX}\`) && \"lifecycle-state\"==\`RUNNING\`].id | []" \
    --raw-output | ALL_VNICS="${ALL_VNICS}" python3 -c "
import json, re, sys, subprocess, os

ids = json.loads(sys.stdin.read())
all_vnics = os.environ.get('ALL_VNICS', 'false').lower() == 'true'

if not ids:
    print('No running instances found matching prefix.', file=sys.stderr)
    sys.exit(0)

vnic_label = 'all VNICs' if all_vnics else 'primary VNIC only'
print(f'# Fetching {vnic_label} per instance', file=sys.stderr)

# Primary-only filter vs all VNICs
if all_vnics:
    vnic_query = 'data[].{\"Name\":\"display-name\",\"Private IP\":\"private-ip\",\"Public IP\":\"public-ip\"}'
else:
    vnic_query = 'data[?\"is-primary\"==\`true\`].{\"Name\":\"display-name\",\"Private IP\":\"private-ip\",\"Public IP\":\"public-ip\"}'

rows = []   # (instance_num, name, private_ip, public_ip)

for iid in ids:
    result = subprocess.run(
        [
            'oci', 'compute', 'instance', 'list-vnics',
            '--instance-id', iid.strip(),
            '--query', vnic_query,
            '--raw-output'
        ],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f'WARNING: list-vnics failed for {iid}: {result.stderr.strip()}', file=sys.stderr)
        continue
    if not result.stdout.strip():
        continue
    vnics = json.loads(result.stdout)
    for v in vnics:
        name       = v.get('Name', '')       or ''
        private_ip = v.get('Private IP', '') or ''
        public_ip  = v.get('Public IP', '')  or ''
        # Extract the trailing integer from the display-name to preserve
        # instance ordering (e.g. 'cluster-abc-1' → 1, 'node-pool-def-12' → 12).
        m = re.search(r'(\d+)\D*$', name)
        instance_num = int(m.group(1)) if m else len(rows) + 1
        rows.append((instance_num, name, private_ip, public_ip))

# Sort by the trailing instance number so output order is deterministic
# and matches OCI display-name numbering (instance-1 before instance-2, etc.)
rows.sort(key=lambda r: r[0])

print('Name,Private IP,Public IP')
private_ips = []
public_ips  = []
for instance_num, name, private_ip, public_ip in rows:
    print(f'{name},{private_ip},{public_ip}')
    if private_ip: private_ips.append(private_ip)
    if public_ip:  public_ips.append(public_ip)

print()
print('# Private IPs (single line)')
print(','.join(private_ips))
print()
print('# Public IPs (single line)')
print(','.join(public_ips))
print()
print('# Instance mapping (instance-number:name:public-ip)')
for instance_num, name, private_ip, public_ip in rows:
    if public_ip:
        print(f'{instance_num}:{name}:{public_ip}')
" | run
