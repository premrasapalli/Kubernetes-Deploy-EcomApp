# [TELUGU EXPLANATION]
# PURPOSE      : Platform components folder
# WHAT IT DOES : Cilium, Gateway API, External Secrets, Observability setup
# WHY ENTERPRISE: Cluster add-ons/platform layer
# HOW TO USE   : Phase 3 లో fill చేయడం
# NOTES        : AWS Free-Tier mindful, minimal configs

# 04-platform/README.md

## Folder Purpose (లక్ష్యం)
ఈ folder లో **EKS cluster కి install చేసే platform components** ని manage చేస్తాము.

Terraform తో cluster create చేసిన తర్వాత **platform bootstrap** చేస్తాము.

## Components
| Component | Folder | Purpose (Telugu) | Notes |
| --- | --- | --- | --- |
| **Cilium** | `cilium/` | CNI + NetworkPolicy + L7 + Gateway API controller + Hubble | **Core**. kube-proxy replacement |
| **Gateway API** | `gateway-api/` | GatewayClass/Gateway/HTTPRoute manifests + CRD notes | Cilium తో attach |
| **External Secrets** | `external-secrets/` | ESO install + SecretStore/ExternalSecret | AWS SM integration |
| **cert-manager** | `cert-manager/` | TLS automation (add only if needed) | Optional for now |
| **kube-prometheus-stack** | `kube-prometheus-stack/` | Prometheus/Grafana/Alertmanager | Observability (minimal) |
| **scripts/` | `scripts/` | Platform install helpers | Automation |

## Files we'll create (Phase 3)
| File | Purpose |
| --- | --- |
| `cilium/values-cilium.yaml` | Cilium helm values (native + kpr + gatewayAPI + hubble) |
| `cilium/install-cilium.sh` | Install/upgrade Cilium |
| `gateway-api/install-gatewayapi-crds.sh` | Gateway API experimental/standard CRDs (version aware) |
| `gateway-api/gatewayclass.yaml` | Cilium GatewayClass |
| `external-secrets/install-eso.sh` | ESO Helm install |
| `external-secrets/secretstore-aws-sm.yaml` | SecretStore for AWS Secrets Manager (IRSA) |
| `kube-prometheus-stack/values-kps.yaml` | Minimal values (resource mindful) |

## Enterprise Notes (Telugu)
- **Cilium Native** - AWS-CNI chaining వద్దు. Gateway API కి full Cilium అవసరం
- **kubeProxyReplacement: true** - Mandatory for Gateway API
- **k8sServiceHost/Port** - kube-proxy లేకపోతే తప్పనిసరి
- **Gateway API CRDs** - Cilium version కి match అయ్యేలా install
- **IRSA for ESO** - AWS Secrets Manager access కోసం
- **Hubble** - Network flows debug కి అత్యంత ఉపయోగకరం

## Usage
```bash
# Phase 3 order roughly
# 1) Cilium
# 2) Gateway API CRDs
# 3) External Secrets
# 4) kube-prometheus-stack (optional/minimal)
```

**Rule:** Helm values + scripts కి `[TELUGU EXPLANATION]` block + inline comments తప్పనిసరి.
