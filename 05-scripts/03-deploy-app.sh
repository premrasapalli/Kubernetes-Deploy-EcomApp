#!/usr/bin/env bash
# ── తెలుగు వివరణ ─────────────────────────────────────────────
# App deploy క్రమం: namespace/SA/policies → Gateway → HTTPRoute → workloads.
# İmaj placeholders (IMAGE_PREFIX/IMAGE_TAG) ను ECR URL మరియు tag తో replace చేస్తుంది.
# ─────────────────────────────────────────────────────────────
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="${TAG:-v1}"

REGISTRY="$(terraform -chdir="$ROOT/01-terraform-eks" output -raw ecr_registry)"

echo "==> Applying namespace, RBAC, config, workloads"
kubectl kustomize "$ROOT/03-k8s-manifests/overlays/dev" \
  | sed -e "s|IMAGE_PREFIX|${REGISTRY}|g" -e "s|IMAGE_TAG|${TAG}|g" \
  | kubectl apply -f -

echo "==> Applying GatewayClass, LB IPAM, Gateway, HTTPRoute"
kubectl apply -f "$ROOT/04-platform/gateway-api/gatewayclass.yaml"
kubectl apply -f "$ROOT/04-platform/gateway-api/lb-ipam.yaml"
kubectl apply -f "$ROOT/04-platform/gateway-api/gateway.yaml"
kubectl apply -f "$ROOT/04-platform/gateway-api/httproute.yaml"

echo "==> Waiting for ExternalSecrets to sync"
kubectl -n retailx wait --for=condition=Ready externalsecret/postgres-credentials --timeout=180s
kubectl -n retailx wait --for=condition=Ready externalsecret/jwt-secret --timeout=180s

echo "==> Waiting for workloads"
kubectl -n retailx rollout status deploy/frontend --timeout=5m
kubectl -n retailx rollout status deploy/product-api --timeout=5m
kubectl -n retailx rollout status deploy/cart-api --timeout=5m
kubectl -n retailx rollout status deploy/order-api --timeout=5m
kubectl -n retailx rollout status deploy/nettest --timeout=5m
kubectl -n retailx rollout status statefulset/postgres --timeout=5m
kubectl -n retailx rollout status statefulset/redis --timeout=5m

echo "==> Deployed"
kubectl -n retailx get pods -o wide
kubectl get gateway,httproute -n retailx
