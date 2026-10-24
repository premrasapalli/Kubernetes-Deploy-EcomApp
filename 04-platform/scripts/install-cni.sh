#!/usr/bin/env bash
# ── తెలుగు వివరణ ─────────────────────────────────────────────
# CNI బూట్‌స్ట్రాప్: Gateway API CRDs మొదట, ఆపై Cilium (kube-proxy replacement).
# ఇది nodes రాకముందే నడపాలి — nodes వచ్చాక Cilium వెంటనే pod network ఇస్తుంది.
# --wait వాడము: nodes లేకపోతే operator pod pending లో ఉంటుంది.
# ─────────────────────────────────────────────────────────────
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-retailx-eks}"
REGION="${REGION:-us-east-1}"
CILIUM_VERSION="${CILIUM_VERSION:-1.20.2}"
GATEWAY_API_VERSION="${GATEWAY_API_VERSION:-v1.5.1}"

echo "==> Installing Gateway API ${GATEWAY_API_VERSION} experimental CRDs"
kubectl apply --server-side -f \
  "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/experimental-install.yaml"

ENDPOINT="$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" \
  --query 'cluster.endpoint' --output text)"
K8S_HOST="${ENDPOINT#https://}"

echo "==> Installing Cilium ${CILIUM_VERSION} (kubeProxyReplacement=true)"
helm repo add cilium https://helm.cilium.io/ >/dev/null 2>&1 || true
helm repo update cilium >/dev/null

helm upgrade --install cilium cilium/cilium \
  --version "$CILIUM_VERSION" \
  --namespace kube-system \
  -f "$ROOT/04-platform/cilium/values.yaml" \
  --set cluster.name="$CLUSTER_NAME" \
  --set k8sServiceHost="$K8S_HOST" \
  --set k8sServicePort=443

echo "==> Cilium chart installed (pods will start after nodes join)"
