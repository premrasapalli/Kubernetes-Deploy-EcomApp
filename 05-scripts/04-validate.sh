#!/usr/bin/env bash
# ── తెలుగు వివరణ ─────────────────────────────────────────────
# End-to-end ధృవీకరణ:
# 1) Gateway ACCEPTED/PROGRAMMED, HTTPRoute Accepted.
# 2) Gateway ద్వారా frontend 200, /admin 403 (L7 policy).
# 3) Gateway ద్వారా APIs 200/201.
# 4) Direct service (Gateway bypass) 200 — nginx.
# 5) ESO secrets, HPA, PDB.
# ─────────────────────────────────────────────────────────────
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GW_IP="$(terraform -chdir="$ROOT/01-terraform-eks" output -raw gateway_ip)"
HOST_HEADER="retailx.example.com"
NS="retailx"

run() { kubectl -n "$NS" exec deploy/nettest -- "$@"; }

echo "==> Gateway status"
kubectl get gatewayclass
kubectl -n "$NS" get gateway,httproute

echo "==> Gateway -> frontend (expect 200 + envoy)"
run curl -sS -o /dev/null -w '%{http_code} %{header_json}\n' -H "Host: $HOST_HEADER" "http://${GW_IP}/" \
  | tr ',' '\n' | grep -Ei 'http_code|server' || true

echo "==> Gateway blocked path /admin (expect 403)"
run curl -sS -o /dev/null -w '%{http_code}\n' -H "Host: $HOST_HEADER" "http://${GW_IP}/admin"

echo "==> Gateway -> product API (expect 200)"
run curl -sS -H "Host: $HOST_HEADER" "http://${GW_IP}/api/products"

echo "==> Gateway -> cart API POST (expect 201)"
run curl -sS -X POST -H "Host: $HOST_HEADER" -H 'content-type: application/json' \
  -d '{"productId":1,"quantity":2}' "http://${GW_IP}/api/cart/demo/items"

echo "==> Gateway -> order API POST (expect 201)"
run curl -sS -X POST -H "Host: $HOST_HEADER" -H 'content-type: application/json' \
  -d '{"userId":"demo","productId":1,"quantity":1}' "http://${GW_IP}/api/orders"

echo "==> Direct service DNS (expect 200 + nginx)"
run curl -sS -o /dev/null -w '%{http_code}\n' "http://frontend.${NS}.svc.cluster.local/"

echo "==> Secrets synced"
kubectl -n "$NS" get externalsecret
kubectl -n "$NS" get secret postgres-credentials jwt-secret

echo "==> HPA / PDB"
kubectl -n "$NS" get hpa
kubectl -n "$NS" get pdb

echo "Validation complete"
