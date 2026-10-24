#!/usr/bin/env bash
# ── తెలుగు వివరణ ─────────────────────────────────────────────
# నాలుగు ఇమేజ్‌లను build చేసి ECR కి push. EKS nodes x86 → --platform linux/amd64.
# TAG డిఫాల్ట్ v1; ప్రొడక్షన్ లో git SHA వాడాలి (immutable tags).
# ─────────────────────────────────────────────────────────────
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGION="${REGION:-us-east-1}"
TAG="${TAG:-v1}"
SERVICES=(frontend product-api cart-api order-api)

REGISTRY="$(terraform -chdir="$ROOT/01-terraform-eks" output -raw ecr_registry)"
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY" >/dev/null

for svc in "${SERVICES[@]}"; do
  echo "==> Building $svc:$TAG"
  docker build --platform linux/amd64 \
    -t "$REGISTRY/retailx/$svc:$TAG" \
    "$ROOT/02-app-source/$svc"
  docker push "$REGISTRY/retailx/$svc:$TAG"
done

echo "Pushed all images with tag $TAG to $REGISTRY"
