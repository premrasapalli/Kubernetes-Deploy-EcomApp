#!/usr/bin/env bash
# ── తెలుగు వివరణ ─────────────────────────────────────────────
# పూర్తి teardown: K8s workloads → EBS PVCలు → Terraform infra.
# EKS ఖర్చు ఆపడానికి ఇది తప్పనిసరి. ECR force_delete, Secrets recovery_window=0.
# ─────────────────────────────────────────────────────────────
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Deleting app + platform resources"
kubectl delete -f "$ROOT/04-platform/gateway-api/httproute.yaml" --ignore-not-found || true
kubectl delete -f "$ROOT/04-platform/gateway-api/gateway.yaml" --ignore-not-found || true
kubectl delete -k "$ROOT/03-k8s-manifests/overlays/dev" --ignore-not-found || true

echo "==> Waiting for LoadBalancer/PVC cleanup"
sleep 20
kubectl get pvc -n retailx 2>/dev/null || true

echo "==> Terraform destroy (EKS, VPC, ECR, IAM, secrets)"
terraform -chdir="$ROOT/01-terraform-eks" destroy -auto-approve -input=false

echo "==> Remaining EKS clusters"
aws eks list-clusters --region "${REGION:-us-east-1}" --output text
echo "Teardown complete"
