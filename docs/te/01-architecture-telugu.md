# [TELUGU EXPLANATION]
# PURPOSE      : retailx ప్రాజెక్ట్ యొక్క Architecture doc
# WHAT IT DOES : High Level Design, Low Level Design, Traffic Flow, Trust Model వివరంగా తెలుగులో చూపిస్తుంది
# WHY ENTERPRISE: Enterprise లో ఎలా design చేస్తారో తెలుసుకోవడానికి
# HOW TO USE   : ప్రతి phase ముందు ఈ doc reference గా use చేయి
# NOTES        : Project ముందుకు వెళ్లే కొద్దీ update చేస్తూనే ఉండాలి

# ARCHITECTURE.md - retailx Enterprise Kubernetes Architecture

## 1) Objective (లక్ష్యం)
AWS EKS పై **retailx** అనే enterprise-style e-commerce microservices ని zero నుండి build చేసి deploy చేయడం.

ఈ doc ద్వారా మనం HLD, LLD, Traffic Flow, Security/Trust Model అర్థం చేసుకుంటాము.

## 2) High Level Design (HLD)

```
[User Browser] --> [Cilium Gateway API (L4/L7)] --> [HTTPRoute] --> [Services] --> [Pods]
                        |                        |                |           |
                       LB IPAM                Routing Rules    ClusterIP   App + DB/Redis
```

### Components Overview
| Layer | Component | Description (Telugu) |
| --- | --- | --- |
| **IaC** | Terraform | VPC, EKS, IRSA, ECR create చేస్తుంది |
| **Networking (CNI)** | Cilium (Native + kube-proxy replacement) | Pod networking, NetworkPolicy, L7 filtering (Gateway), Hubble flows |
| **Traffic Entry** | Gateway API (Cilium Gateway Controller) | Ingress తరహా modern API. HTTPRoute ద్వారా route చేస్తాము |
| **Apps** | Microservices (frontend, product-api, cart-api, order-api) | Business logic |
| **Data** | Postgres (StatefulSet), Redis (StatefulSet) | Persistent + Cache data |
| **Secrets** | External Secrets Operator + AWS Secrets Manager | Secrets ని securely inject చేస్తాము |
| **Identity** | IRSA | Pod కి AWS permissions ఇవ్వడానికి (least privilege) |
| **Security** | PSS Restricted, RBAC, CiliumNetworkPolicy | Zero-trust |
| **Resiliency** | Probes, Resources, PDB, HPA, TopologySpreadConstraints | High availability mindset |

## 3) Low Level Design (LLD)

### 3.1 Network Topology (AWS)
| Resource | Choice (Free-Tier Aware) | Notes (Telugu) |
| --- | --- | --- |
| **VPC** | Custom VPC (10.0.0.0/16) | Enterprise లాగా private/public split |
| **Public Subnets** | NAT Gateway, Load Balancer related (minimal) | Outbound కోసం మాత్రమే use |
| **Private Subnets** | EKS Worker Nodes | Nodes ఎప్పుడూ public expose చేయము |
| **NAT Gateway** | **1 NAT Gateway** (cost aware) | Free-Tier దగ్గరగా trade-off. Enterprise లో multi-AZ వుంటుంది |
| **EKS API** | Private endpoint (where possible) + controlled access | Hardened approach |
| **Node Group** | Managed Node Group, `t3.small`, min:1, desired:1-2, max:2 | Minimal but realistic |

### 3.2 Kubernetes Namespaces
All app components `retailx` namespace లో ఉంటాయి. Platform components (`kube-system`, `external-secrets`, `monitoring`) వేరు.

### 3.3 Microservices Details
| Service | Image | Port | Replicas (initial) | DB/Cache | Notes |
| --- | --- | --- | --- | --- | --- |
| **frontend** | `retailx/frontend` | 8080 (nginx) | 2 | - | Static UI, calls APIs |
| **product-api** | `retailx/product-api` | 8080 | 2 | Postgres | Products CRUD (read heavy) |
| **cart-api** | `retailx/cart-api` | 8080 | 2 | Redis | Cart operations |
| **order-api** | `retailx/order-api` | 8080 | 2 | Postgres | Orders create/list |
| **postgres** | `postgres` (or official) | 5432 | 1 (StatefulSet) | - | Learning focus, enterprise లో managed (RDS) కానీ K8s లో practice |
| **redis** | `redis` | 6379 | 1 (StatefulSet) | - | Cache/Session store |

### 3.4 Traffic Flow (Step by Step)
1. Client hits Gateway IP (Cilium LB IPAM assigned) on port 80
2. **Gateway (Cilium)** accepts request (Listener HTTP)
3. **HTTPRoute** matches `PathPrefix /` -> routes to `frontend` Service
4. Frontend (browser JS) calls internal APIs via Service DNS (`product-api.retailx.svc.cluster.local:8080`)
5. **Cilium L7/eBPF + NetworkPolicies** enforce allowed traffic only
6. APIs talk to Postgres/Redis as per policy
7. Response flows back same path

### 3.5 Security & Trust Model (Zero Trust)
| Control | Implementation | Explanation (Telugu) |
| --- | --- | --- |
| **Pod Identity** | IRSA per ServiceAccount | IAM role directly to Pod. Node IAM role expand చేయము |
| **Least Privilege RBAC** | Role/RoleBinding per app | అవసరమైన verbs/resources మాత్రమే |
| **Pod Security** | Pod Security Admission - `restricted` (where applicable) | runAsNonRoot, drop ALL caps, readOnlyRootFS etc |
| **Network Segmentation** | DefaultDeny + allow rules (K8s NP + CiliumNetworkPolicy) | Pod-to-Pod unrestricted ఉండకూడదు |
| **L7 Gateway Policy** | Cilium L7 HTTP rules (like before) | Method/Path based allow/deny |
| **Secrets** | External Secrets (no plain K8s Secret with values in Git) | AWS Secrets Manager as source |
| **Image** | Pull from ECR (private) | Controlled registry |
| **Probes/Resources** | Enforced on all workloads | No unbounded pods |

## 4) Tech Stack Summary
| Category | Tool/Tech | Reason |
| --- | --- | --- |
| **Cloud** | AWS (EKS, VPC, ECR, IAM, Secrets Manager) | Real enterprise cloud |
| **IaC** | Terraform | Declarative, reproducible |
| **Orchestration** | Kubernetes 1.36 (EKS) | Industry standard |
| **CNI/Gateway** | Cilium | All-in-one (CNI+NP+L7+Gateway+Hubble) |
| **Packaging** | Docker, ECR | Container flow |
| **Config** | Kustomize | Simple overlays |
| **GitOps ready** | Structure laid out | Future scope |
| **Observability** | kube-prometheus-stack + Hubble | Metrics + network visibility |

## 5) Open Questions / Notes
- **DB in Cluster vs RDS:** Learning కోసం Postgres/Redis ని K8s లో deploy చేస్తాము. Enterprise traceability కోసం notes add చేస్తాము
- **cert-manager:** అవసరం felt అయితే మాత్రమే add చేస్తాము (cost/free context)
- **Multi-AZ:** Enterprise default కానీ Free-Tier mindful గా minimal
- **WAF/PrivateLink:** Out of scope for this learning project

**Update Rule:** ఈ doc ని ప్రతి major phase complete అయినప్పుడు update చేస్తూనే వుంటాము.
