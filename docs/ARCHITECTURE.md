# RetailX Architecture

> Status: living document. Implementation notes are in Section 11 (actual state).

## 1. Goals and non-goals

### Goals
- Demonstrate the patterns enterprises use on EKS: least privilege, zero-trust networking,
  declarative infra, GitOps-friendly manifests, full observability.
- Be cheap enough to run on a personal AWS account and destroyed after each session.
- Teach debugging: every component is observable and every failure is documented.

### Non-goals
- Multi-region / multi-cluster (mentioned, not built).
- Service mesh (Cilium L7 replaces it for this lab; Istio notes added later).
- CI/CD server (we use local scripts + ECR; GitHub Actions notes added later).

## 2. High-level design

```text
                       Internet
                          |
                    [ Gateway API ]
                    Cilium + Envoy
                  LB IPAM: 10.0.x.250
                          |
          +---------------+----------------+
          |               |                |
     frontend        product-api       order-api
     (nginx)         (node/express)    (node/express)
          |               |                |
          |           cart-api              |
          |          (node/express)         |
          |               |                |
          |            [ Redis ]      [ PostgreSQL ]
          |          StatefulSet      StatefulSet
          |               |                |
          +------- CiliumNetworkPolicies --+
                (default-deny + explicit allow)
```

## 3. Component responsibilities

| Layer | Component | Responsibility | Why this choice |
|---|---|---|---|
| Infra | Terraform | VPC, EKS, node group, IAM, ECR | Reproducible, reviewable, destroyable |
| CNI | Cilium | Pod network, kube-proxy replacement, policy, L7 | One tool for CNI + NetworkPolicy + Gateway |
| Ingress | Gateway API (Cilium) | HTTP routing, hostnames, path match | Successor to Ingress; role-oriented |
| LB | Cilium LB IPAM + L2 | Assign a stable VIP to Gateway | No AWS LB cost/complexity in lab |
| Secrets | External Secrets Operator | Sync AWS Secrets Manager -> K8s | No secrets in Git |
| AWS auth | IRSA | Scoped IAM per ServiceAccount | No node-wide AWS credentials |
| Packaging | Docker + ECR | Immutable images | Standard enterprise flow |
| Config | Kustomize | base + overlays | No templating language to learn |
| Observability | kube-prometheus-stack + Hubble | Metrics, alerts, flow logs | Debug both app and network |

## 4. Trust model (zero trust)

```text
default deny (ingress + egress)
        |
        +-- frontend        <- Gateway (reserved:ingress) on 8080, L7 GET /
        +-- product-api     <- frontend only, 8081
        +-- cart-api        <- frontend only, 8082
        +-- order-api       <- frontend only, 8083
        +-- redis           <- cart-api only, 6379
        +-- postgres        <- product-api + order-api only, 5432
        +-- all pods        -> DNS (kube-dns :53) only
```

- Each service has its own ServiceAccount; no `default` SA is used.
- AWS permissions are attached per SA via IRSA.
- Pod Security Admission: `restricted` enforced at namespace level.
- Identity is preserved end-to-end: Gateway L7 proxy keeps the original client
  identity, so policies must allow *both* hops (client -> Gateway and Gateway -> backend).

## 5. Traffic flows

### 5.1 User request
```text
client -> Gateway VIP (Envoy) -> HTTPRoute -> Service -> Pod
```
- TLS termination: `TODO` (cert-manager phase).
- L7 authorization: HTTP method/path allow-list in CiliumNetworkPolicy.

### 5.2 Pod -> AWS (Secrets Manager)
```text
pod -> ESO -> AWS STS (IRSA token) -> Secrets Manager -> K8s Secret -> pod
```
- No long-lived AWS keys anywhere.

### 5.3 Data flows
```text
frontend -> product-api  :8081
frontend -> cart-api     :8082
frontend -> order-api    :8083
cart-api -> redis        :6379
product-api -> postgres  :5432
order-api -> postgres    :5432
```

## 6. Namespaces

| Namespace | Contents |
|---|---|
| `retailx` | Application workloads + policies |
| `platform` | External Secrets Operator, monitoring |
| `kube-system` | Cilium, CoreDNS |

## 7. Key architecture decisions (ADRs)

| # | Decision | Alternatives | Consequence |
|---|---|---|---|
| 1 | Cilium native, kube-proxy replacement | AWS VPC CNI chaining | Gateway API + L7 policy possible; nodes NotReady until Cilium installed |
| 2 | Gateway API, not Ingress | nginx-ingress / ALB Ingress | Modern, L7-native; requires Cilium + CRDs |
| 3 | Cilium LB IPAM, not AWS LB | AWS Load Balancer Controller | Saves ~$18/mo; VIP is not internet-reachable (lab only) |
| 4 | External Secrets + IRSA | Sealed Secrets / plain secrets | Real AWS integration, no keys in Git |
| 5 | Private nodes + 1 NAT (lab) | Public nodes, no NAT | ~$33/mo; required for private image pulls; nodes stay unreachable from internet |
| 6 | 2× spot t3.medium, 2 AZs (lab) | Multi-AZ on-demand, 3+ nodes | ~$20/mo; survives one node loss, still not production HA |
| 7 | Kustomize | Helm | Simpler for app manifests; Helm used only for platform charts |

## 8. Cost model

| Item | Lab (cost-optimized) | Production-like |
|---|---|---|
| EKS control plane | $0.10/hr ≈ $73/mo | same |
| Nodes | 2× t3.medium spot ≈ $18-22/mo | 3× m6i.large ≈ $220/mo |
| NAT Gateway | 1× ≈ $33/mo + data | 3× ~$99/mo + data |
| Load balancer | Cilium LB IPAM (free) | AWS NLB/ALB ~$18/mo |
| EBS | ~$3/mo | ~$30/mo |
| **Total** | **~$125-130/mo; ~$8-12 per weekend session** | **~$400+/mo** |

**Rule:** run `05-scripts/99-teardown.sh` at the end of every session.

## 9. Failure domains

| Failure | Effect | Mitigation |
|---|---|---|
| Cilium not installed | Nodes NotReady, no pod network | Two-stage apply: CNI before nodes (Section 11) |
| One of two nodes dies | Capacity drops; pods reschedule | PDB + 2 AZs; prod = 3+ nodes + topology spread |
| Gateway misprogrammed | 503 / no address | Check GatewayClass ACCEPTED, LB IPAM pool, CRD version |
| Policy too strict | 403 from Envoy / drops | Hubble verdicts + both-hop rules |
| IRSA misconfigured | ESO auth errors | Check SA annotation, role trust policy, OIDC provider |

## 10. Open questions / TODO

- [ ] TLS + hostname (cert-manager + ACM?)
- [ ] Autoscaling: HPA vs KEDA; cluster autoscaler vs Karpenter
- [ ] CI/CD pipeline and image signing (cosign)
- [ ] Backup/restore for Postgres (Velero / pgBackRest)
- [ ] Multi-environment overlays (dev/stage/prod)

## 11. Implementation notes (actual)

### 11.1 Bootstrap order (why two Terraform applies)
```text
terraform apply -var node_desired_size=0
  -> VPC, EKS control plane, OIDC/IRSA, ECR, Secrets Manager
install Gateway API CRDs + Cilium (no --wait, no nodes yet)
terraform apply -var node_desired_size=2
  -> managed node group joins; Cilium agent is already the CNI
```
Reason: EKS nodes need a CNI to become `Ready`. With
`bootstrap_self_managed_addons=false` (module v21 hardcodes this) there is no
`aws-node`; Cilium must exist first. Cilium is configured with
`ipam.mode=kubernetes` so the agent can start using node/pod CIDRs before the
Cilium operator is schedulable. `kubeProxyReplacement=true` makes Cilium own
Service routing, which Gateway API requires (Issue #0).

### 11.2 Networking as built
- VPC `10.0.0.0/16`; private `10.0.11.0/24`, `10.0.12.0/24`; public `10.0.1.0/24`, `10.0.2.0/24`.
- One NAT Gateway in the first public subnet; both private route tables use it.
- Cluster endpoint: public, CIDR-restricted by `cluster_endpoint_public_access_cidrs`.
- Gateway VIP `10.0.11.250` (in private subnet 1) via Cilium LB IPAM + L2 announcement.
  Reachable from inside the VPC only — use `nettest` or SSM port-forward, not the internet.
- Cilium `routingMode=tunnel` (VXLAN); no native-routing ENI prerequisites.

### 11.3 Platform addons
| Addon | Install | Notes |
|---|---|---|
| metrics-server | Helm, `--kubelet-insecure-tls` | HPA needs metrics; lab uses self-signed kubelet certs |
| External Secrets Operator | Helm, CRDs, SA `platform/external-secrets` | IRSA role `${project}-eso`; `external-secrets.io/v1` |
| EBS CSI driver | EKS managed addon + IRSA | `gp3` default StorageClass |
| Cilium LB IPAM / Gateway API | Cilium chart + CRDs v1.5.1 experimental | Applied by `04-platform/scripts/install-addons.sh` |
| kube-prometheus-stack | Optional (`INSTALL_MONITORING=true`) | Heavy; not part of default lab |

### 11.4 Application packaging
- Namespace `retailx`: Pod Security `restricted`; namespace `platform`: `baseline`.
- Images `IMAGE_PREFIX/retailx/<service>:IMAGE_TAG` are placeholders replaced at deploy.
- Workloads: frontend (3), each API (2), PostgreSQL/Redis StatefulSets (1 each), nettest (1).
- Every app SA has `automountServiceAccountToken: false`; only `nettest` has RBAC.

### 11.5 Destroy checklist
`05-scripts/99-teardown.sh` deletes routes/Gateway/workloads, waits for PVC and
LB cleanup, then `terraform destroy` (ECR `force_delete`, Secrets
`recovery_window_in_days=0`). Confirm `aws eks list-clusters` is empty.

---

## తెలుగు సారాంశం

- **లక్ష్యం:** ఎంటర్‌ప్రైజ్ పద్ధతులను నేర్పడం — least privilege, zero-trust networking, declarative infra, observability.
- **Cilium ఎందుకు:** CNI + NetworkPolicy + L7 + Gateway API + Hubble అన్నీ ఒకే టూల్‌లో.
- **Gateway API ఎందుకు:** పాత Ingress కంటే శక్తివంతం; role-based, L7 rules సులభం.
- **LB IPAM ఎందుకు:** AWS Load Balancer ఖర్చు తగ్గించడానికి; ల్యాబ్‌కు సరిపోతుంది.
- **IRSA + External Secrets:** AWS సీక్రెట్స్‌ను Git లో పెట్టకుండా సురక్షితంగా వాడటానికి.
- **రెండు హాప్‌ల పాలసీ:** క్లయింట్ → గేట్‌వే, గేట్‌వే → బ్యాకెండ్ — రెండూ allow చేయాలి; లేకపోతే 403.
- **ఖర్చు:** ల్యాబ్‌లో సెషన్‌కు ~$5–8; వాడకపోతే destroy చేయాలి.
- **ప్రొడక్షన్ తేడా:** ప్రైవేట్ సబ్‌నెట్స్ + NAT + బహుళ నోడ్స్ + ఆటోస్కేలింగ్; ఇక్కడ నేర్చుకోవడానికి సింపుల్ చేశాం.
