#!/usr/bin/env bash
# ── తెలుగు వివరణ ─────────────────────────────────────────────
# ఏదైనా సృష్టించే ముందు అవసరమైన టూల్స్ + AWS identity + Docker check.
# EKS ఉచితం కాదు — ఖర్చు హెచ్చరిక చూపిస్తుంది.
# ─────────────────────────────────────────────────────────────
set -euo pipefail

need() { command -v "$1" >/dev/null 2>&1 || { echo "MISSING: $1"; exit 1; }; }

for bin in aws terraform kubectl helm docker; do need "$bin"; done
docker info >/dev/null 2>&1 || { echo "Docker daemon not running"; exit 1; }

echo "==> AWS identity"
aws sts get-caller-identity
echo "==> Region: $(aws configure get region || echo us-east-1)"
echo
echo "WARNING: EKS control plane costs ~\$0.10/hour (~\$73/month)."
echo "This lab is designed to be destroyed after each session: 05-scripts/99-teardown.sh"
echo
echo "Preflight OK"
