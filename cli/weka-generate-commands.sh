#!/usr/bin/env bash
# Generate a preview of all kubectl/helm commands for phases 4-9
# with all variables expanded to their current values.
# Output goes to stdout and to deploy/cmd.out
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=weka-lib.sh
source "${SCRIPT_DIR}/weka-lib.sh"

OUTPUT_FILE="${SCRIPT_DIR}/cmd.out"


# Route all output through tee so it goes to both stdout and cmd.out
exec > >(tee "${OUTPUT_FILE}") 2>&1

# ── Helpers ───────────────────────────────────────────────────────────────────
section() {
  echo ""
  echo "════════════════════════════════════════════"
  echo "  Phase $1: $2"
  echo "════════════════════════════════════════════"
  echo ""
}

# Resolve vars that may not be set; show a placeholder if absent
quay_user="${QUAY_USERNAME:-<QUAY_USERNAME>}"
quay_pass="${QUAY_PASSWORD:-<QUAY_PASSWORD>}"

echo "# Generated: $(date)"
echo "# WEKA_OPERATOR_VERSION : ${WEKA_OPERATOR_VERSION}"
echo "# DEPLOY_DIR            : ${DEPLOY_DIR}"
echo "# QUAY_USERNAME         : ${quay_user}"

# ── Phase 4: Install WEKA operator CRDs ──────────────────────────────────────
section 4 "Install WEKA operator CRDs (${WEKA_OPERATOR_VERSION})"

# Note: inside <<EOF (unquoted), \<newline> is consumed — use \\ to emit a literal \
cat <<EOF
helm show crds \\
  oci://quay.io/weka.io/helm/weka-operator \\
  --version "${WEKA_OPERATOR_VERSION}" \\
| kubectl apply --server-side -f -
EOF
echo ""

cat <<'EOF'
kubectl get crds | grep -i weka
EOF
echo ""

# ── Phase 5: Create namespaces + Quay.io image pull secrets ──────────────────
section 5 "Create namespaces + Quay.io image pull secrets"

cat <<'EOF'
kubectl create namespace weka-operator-system \
  --dry-run=client -o yaml \
| kubectl apply -f -
EOF
echo ""

cat <<EOF
kubectl create secret docker-registry quay-io-robot-secret \\
  --docker-server=quay.io \\
  --docker-username="${quay_user}" \\
  --docker-password="${quay_pass}" \\
  --docker-email="${quay_user}" \\
  --namespace=weka-operator-system \\
  --dry-run=client -o yaml \\
| kubectl apply -f -
EOF
echo ""

cat <<EOF
kubectl create secret docker-registry quay-io-robot-secret \\
  --docker-server=quay.io \\
  --docker-username="${quay_user}" \\
  --docker-password="${quay_pass}" \\
  --docker-email="${quay_user}" \\
  --namespace=default \\
  --dry-run=client -o yaml \\
| kubectl apply -f -
EOF
echo ""

# ── Phase 6: Helm install WEKA operator ──────────────────────────────────────
section 6 "Helm install WEKA operator (${WEKA_OPERATOR_VERSION})"

cat <<EOF
helm upgrade --install weka-operator \\
  oci://quay.io/weka.io/helm/weka-operator \\
  --namespace weka-operator-system \\
  --version "${WEKA_OPERATOR_VERSION}" \\
  --set imagePullSecret=quay-io-robot-secret \\
  --set csi.installationEnabled=true \\
  -f deploy/operator-helm-values.yaml \\
  --wait \\
  --timeout 5m0s
EOF
echo ""

cat <<'EOF'
kubectl rollout status deployment/weka-operator-controller-manager \
  -n weka-operator-system \
  --timeout=300s
EOF
echo ""

cat <<'EOF'
kubectl get pods -n weka-operator-system
EOF
echo ""

# ── Phase 7: Sign Drives ──────────────────────────────────────────────────────
section 7 "Sign Drives — apply WekaPolicy"

cat <<EOF
kubectl apply -f "${DEPLOY_DIR}/sign-drives.yaml"
EOF
echo ""

cat <<'EOF'
kubectl get wekapolicy sign-all-drives-policy -n default
EOF
echo ""

# ── Phase 8: Deploy WekaCluster CR ───────────────────────────────────────────
section 8 "Deploy WekaCluster CR"

cat <<EOF
kubectl apply -f "${DEPLOY_DIR}/weka-cluster.yaml"
EOF
echo ""

echo "# Polling loop — runs every 15s until Ready (timeout: ${WEKACLUSTER_TIMEOUT:-1200}s)"
cat <<'EOF'
kubectl get wekacluster cluster-dev \
  -n default \
  -o jsonpath='{.status.status}'
EOF
echo ""

echo "# On Ready:"
cat <<'EOF'
kubectl get wekacluster cluster-dev -n default
EOF
echo ""

echo "# On Error/Failed:"
cat <<'EOF'
kubectl get wekacluster cluster-dev \
  -n default \
  -o jsonpath='{.status.conditions}' | python3 -m json.tool
EOF
echo ""

# ── Phase 9: Deploy WekaClient CR ────────────────────────────────────────────
section 9 "Deploy WekaClient CR"

cat <<EOF
kubectl apply -f "${DEPLOY_DIR}/weka-client.yaml"
EOF
echo ""

cat <<'EOF'
kubectl get wekaclient cluster-clients -n default
EOF
echo ""

cat <<'EOF'
kubectl get pods -n default
EOF
echo ""

echo "# ────────────────────────────────────────────"
echo "# Commands written to: ${OUTPUT_FILE}"
