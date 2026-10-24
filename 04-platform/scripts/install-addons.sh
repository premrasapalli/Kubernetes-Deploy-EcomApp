#!/usr/bin/env bash
# ── తెలుగు వివరణ ─────────────────────────────────────────────
# Nodes Ready అయ్యాక platform addons:
# 1) metrics-server → HPA కి CPU metrics.
# 2) External Secrets Operator + IRSA SA → AWS Secrets Manager sync.
# 3) Cilium LB IPAM pool → Gateway VIP.
# 4) (optional) kube-prometheus-stack.
# ─────────────────────────────────────────────────────────────
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGION="${REGION:-us-east-1}"
INSTALL_MONITORING="${INSTALL_MONITORING:-false}"

# hostNetwork + 4443: the EKS control plane cannot reach Cilium overlay pod IPs.
# 4443 is already allowed from the cluster SG to nodes (Issue #5).
echo "==> Installing metrics-server"
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ >/dev/null 2>&1 || true
helm repo update metrics-server >/dev/null
helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  --set hostNetwork.enabled=true \
  --set containerPort=4443 \
  --set 'args[0]=--kubelet-insecure-tls' \
  --wait --timeout 5m

echo "==> Creating platform namespace + External Secrets IRSA ServiceAccount"
kubectl create namespace platform --dry-run=client -o yaml | kubectl apply -f -

ESO_ROLE_ARN="$(terraform -chdir="$ROOT/01-terraform-eks" output -raw eso_role_arn)"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-secrets
  namespace: platform
  annotations:
    eks.amazonaws.com/role-arn: ${ESO_ROLE_ARN}
EOF

echo "==> Installing External Secrets Operator"
helm repo add external-secrets https://charts.external-secrets.io >/dev/null 2>&1 || true
helm repo update external-secrets >/dev/null
# The API server cannot reach Cilium VXLAN pod IPs, and PSS baseline rejects
# hostNetwork. Disable the admission webhook + CRD conversion webhook (Issue #5).
helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace platform \
  --set installCRDs=true \
  --set serviceAccount.create=false \
  --set serviceAccount.name=external-secrets \
  --set webhook.create=false \
  --set certController.create=false \
  --wait --timeout 5m

kubectl wait --for=condition=Established \
  crd/clustersecretstores.external-secrets.io --timeout=120s

echo "==> Applying ClusterSecretStore + LB IPAM pool"
kubectl apply -f "$ROOT/04-platform/external-secrets/clustersecretstore.yaml"
kubectl apply -f "$ROOT/04-platform/gateway-api/lb-ipam.yaml"

if [[ "$INSTALL_MONITORING" == "true" ]]; then
  echo "==> Installing kube-prometheus-stack (optional, heavy)"
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
  helm repo update prometheus-community >/dev/null
  helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
    --namespace monitoring --create-namespace \
    --set grafana.adminPassword='retailx-admin' \
    --timeout 10m
fi

echo "==> Platform addons installed"
