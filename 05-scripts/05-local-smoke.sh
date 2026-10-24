#!/usr/bin/env bash
# ── తెలుగు వివరణ ─────────────────────────────────────────────
# Phase 1 local smoke test: docker compose తో అన్ని సేవలు లేపి, products list,
# cart add, order create — మూడూ పని చేస్తున్నాయా verify చేస్తుంది. AWS ఖర్చు $0.
# వాడు: ./05-scripts/05-local-smoke.sh          (test తర్వాత stack తీసేస్తుంది)
#       KEEP_UP=1 ./05-scripts/05-local-smoke.sh (inspect కోసం నిలిపి ఉంచుతుంది)
#       ./05-scripts/05-local-smoke.sh --down    (stack ని మాత్రమే తీసేయడం)
# ─────────────────────────────────────────────────────────────
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose -f "$ROOT/02-app-source/docker-compose.yml")
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE=(docker-compose -f "$ROOT/02-app-source/docker-compose.yml")
else
  echo "missing: docker compose plugin or docker-compose binary" >&2
  exit 1
fi
BASE="${BASE:-http://localhost:8080}"
KEEP_UP="${KEEP_UP:-0}"

if [[ "${1:-}" == "--down" ]]; then
  "${COMPOSE[@]}" down -v
  exit 0
fi
if [[ "${1:-}" == "--keep" ]]; then
  KEEP_UP=1
fi

for bin in docker curl; do
  command -v "$bin" >/dev/null || { echo "missing: $bin" >&2; exit 1; }
done

cleanup() {
  if [[ "$KEEP_UP" != "1" ]]; then
    "${COMPOSE[@]}" down -v
  fi
}
trap cleanup EXIT

echo "==> Starting local stack (build if needed)"
"${COMPOSE[@]}" up -d --build

echo "==> Waiting for $BASE/api/products"
ready=0
for _ in $(seq 1 60); do
  if curl -fsS "$BASE/api/products" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 2
done
if [[ "$ready" != "1" ]]; then
  echo "stack did not become ready" >&2
  "${COMPOSE[@]}" ps >&2
  exit 1
fi

echo "==> GET /api/products"
curl -fsS "$BASE/api/products"; echo

echo "==> POST /api/cart/demo/items"
curl -fsS -X POST "$BASE/api/cart/demo/items" \
  -H 'content-type: application/json' \
  -d '{"productId":1,"quantity":2}'; echo

echo "==> GET /api/cart/demo"
curl -fsS "$BASE/api/cart/demo"; echo

echo "==> POST /api/orders"
curl -fsS -X POST "$BASE/api/orders" \
  -H 'content-type: application/json' \
  -d '{"userId":"demo","productId":1,"quantity":1}'; echo

echo "==> GET /api/orders?userId=demo"
curl -fsS "$BASE/api/orders?userId=demo"; echo

echo "OK: products, cart and orders all responded over the frontend proxy."
