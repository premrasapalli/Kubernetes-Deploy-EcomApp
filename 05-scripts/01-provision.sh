#!/usr/bin/env bash
# ── తెలుగు వివరణ ─────────────────────────────────────────────
# పూర్తి provisioning క్రమం (2-stage):
# 1) Terraform: VPC + EKS + ECR + IRSA, nodes desired=0.
# 2) Gateway API CRDs + Cilium (nodes లేకుండా).
# 3) Terraform: nodes desired=2 → Cilium CNI తో Ready.
# 4) platform addons (metrics-server, ESO, LB IPAM).
# ఈ క్రమం వల్ల "CNI లేకుండా nodes" సమస్య రాదు (Issue #1).
# ─────────────────────────────────────────────────────────────
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGION="${REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-retailx-eks}"
NODE_COUNT="${NODE_COUNT:-2}"

echo "==> Terraform init/apply (nodes=0, CNI bootstrap)"
terraform -chdir="$ROOT/01-terraform-eks" init -input=false
terraform -chdir="$ROOT/01-terraform-eks" apply -auto-approve -input=false \
  -var="node_desired_size=0"

echo "==> Updating kubeconfig"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"

echo "==> Installing CNI before nodes"
CLUSTER_NAME="$CLUSTER_NAME" REGION="$REGION" bash "$ROOT/04-platform/scripts/install-cni.sh"

echo "==> Installing EKS addons (CoreDNS, EBS CSI) now that CNI exists"
terraform -chdir="$ROOT/01-terraform-eks" apply -auto-approve -input=false \
  -var="node_desired_size=${NODE_COUNT}" -var="install_addons=true"

# The EKS module ignores scaling_config.desired_size after creation, so the
# variable above does not scale an existing node group. Scale it explicitly.
NODEGROUP="$(aws eks list-nodegroups --cluster-name "$CLUSTER_NAME" --region "$REGION" \
  --query 'nodegroups[0]' --output text)"
echo "==> Scaling nodegroup ${NODEGROUP} to ${NODE_COUNT} (Cilium now provides CNI)"
aws eks update-nodegroup-config --cluster-name "$CLUSTER_NAME" --region "$REGION" \
  --nodegroup-name "$NODEGROUP" \
  --scaling-config "minSize=0,maxSize=3,desiredSize=${NODE_COUNT}" >/dev/null

echo "==> Waiting for nodes Ready"
kubectl wait --for=condition=Ready nodes --all --timeout=15m

echo "==> Waiting for Cilium, operator, CoreDNS"
kubectl -n kube-system rollout status ds/cilium --timeout=10m
kubectl -n kube-system rollout status deploy/cilium-operator --timeout=10m
kubectl -n kube-system rollout status deploy/coredns --timeout=10m

echo "==> Installing platform addons"
REGION="$REGION" bash "$ROOT/04-platform/scripts/install-addons.sh"

echo "==> Cluster ready"
kubectl get nodes -o wide
