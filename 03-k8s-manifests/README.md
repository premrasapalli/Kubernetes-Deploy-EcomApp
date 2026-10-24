# [TELUGU EXPLANATION]
# PURPOSE      : Kubernetes manifests folder (Kustomize based)
# WHAT IT DOES : base + overlays/dev structure
# WHY ENTERPRISE: Environment separation (dev/stage/prod mindset)
# HOW TO USE   : Phase 4 లో fill చేయడం
# NOTES        : PSS, RBAC, NetworkPolicy, PDB, HPA, Resources strictly

# 03-k8s-manifests/README.md

## Folder Purpose (లక్ష్యం)
ఈ folder లో **క్లస్టర్ కి deploy చేసే అన్ని K8s manifests** ఉంటాయి.

**Kustomize** use చేస్తున్నాము - DRY, clean, enterprise common pattern.

## Structure
```text
03-k8s-manifests/
├── base/
│   ├── namespaces/        # retailx namespace
│   ├── rbac/              # SA, Role, RoleBinding per app
│   ├── networkpolicies/   # K8s NetworkPolicy + CiliumNetworkPolicy (where needed)
│   ├── configmaps/        # Non-sensitive config
│   ├── secrets-external/  # ExternalSecret CRs (NO plain secrets)
│   ├── workloads/         # Deployments, StatefulSets
│   ├── services/          # ClusterIP Services
│   ├── pdb/               # PodDisruptionBudget
│   ├── hpa/               # HorizontalPodAutoscaler
│   └── kustomization.yaml
└── overlays/
    └── dev/               # dev specific patches/overrides
```

## Enterprise Requirements (Mandatory)
| Item | Status | Notes (Telugu) |
| --- | --- | --- |
| **Namespace** | Required | `retailx` |
| **ServiceAccount per app** | Required | IRSA attach కోసం |
| **RBAC minimal** | Required | Least privilege |
| **Pod Security Standards (Restricted)** | Required | Pod hardening |
| **Resources (requests/limits)** | Required | QoS + avoid noisy neighbor |
| **Probes** | Required | Liveness/Readiness/Startup |
| **PDB** | Required | Disruption control |
| **HPA** | Required | Scale mindset (test గా) |
| **TopologySpreadConstraints** | Required | Node spread (resiliency) |
| **DefaultDeny + Allow** | Required | Network segmentation |
| **ExternalSecrets** | Required | No secrets in Git |

## Rules
- **Secrets folder** లో plain Secret YAMLs create **చేయకూడదు**
- **ప్రతి workload** కి SA, labels, resources, probes తప్పనిసరి
- **Cilium L7 policy** Gateway side enforcement కోసం use చేస్తాము
- **కోన్ని చోట్ల** K8s NP + CiliumNP రెండూ explain చేస్తాము

## Usage
```bash
# Dev overlay apply
kubectl apply -k overlays/dev/

# Verify
kubectl get all -n retailx
```

**Phase 4** లో fill చేస్తాము.
