# RetailX — Enterprise Kubernetes on AWS EKS

> Build a production-style e-commerce platform from scratch on AWS EKS.
> Learn the *why* behind every component. Every file has a Telugu explanation in
> [`docs/te/`](./docs/te). Document every failure, fix, and the reason the fix works.

**Status:** Phase 3 complete — Cilium, Gateway API, LB IPAM, ESO, metrics-server
running on EKS. kube-prometheus-stack is optional and not installed. App images
are not yet pushed to ECR, so Phase 4 workloads are not serving traffic.

---

## 1. What this is

RetailX is a small but realistic e-commerce app (frontend + product/cart/order APIs +
PostgreSQL + Redis) deployed the way enterprises actually run Kubernetes:

- Cilium CNI with kube-proxy replacement (no chaining mode)
- Gateway API instead of legacy Ingress; L7 policy enforced on both hops
- IRSA + External Secrets (no secrets in Git)
- Pod Security Standards `restricted`, per-service RBAC, probes, limits, PDB, HPA
- Terraform for infra, Kustomize for manifests, Hubble + Prometheus for observability
- Designed to be destroyed after each session (cost-aware)

## 2. Repository layout

```text
.
├── docs/                       # English canonical docs
│   └── te/                     # Telugu explanations (start here for learning)
├── 01-terraform-eks/           # VPC, EKS, IRSA, ECR
├── 02-app-source/              # Microservices + Dockerfiles
├── 03-k8s-manifests/           # Kustomize base/ + overlays/dev
├── 04-platform/                # Cilium, Gateway API, ESO, monitoring
└── 05-scripts/                 # bootstrap / validate / teardown
```

## 3. Phase plan

| Phase | Goal | Cost |
|---|---|---|
| 0 | Workspace, docs, issue template | $0 |
| 1 | Build the app source + images | $0 |
| 2 | Terraform: VPC, EKS, IRSA, ECR | AWS |
| 3 | Platform: Cilium, Gateway API, LB IPAM, ESO, monitoring | AWS |
| 4 | Manifests: RBAC, PSS, policies, workloads, PDB/HPA | AWS |
| 5 | Wire Gateway -> services, validate end to end | AWS |
| 6 | Break/fix, harden, log every issue | AWS |
| 7 | Teardown + rebuild rehearsal | AWS |

## 4. Documentation

| File | Purpose |
|---|---|
| `docs/ARCHITECTURE.md` | Design, traffic flow, trust model, decisions, cost |
| `docs/ISSUES.md` | Strict issue format — root cause + **why only this works** |
| `docs/RUNBOOK.md` | Debug commands and decision trees |
| `docs/LEARNINGS.md` | Notes per phase |
| `docs/te/_TEMPLATE.md` | Telugu explanation format (line-by-line) |
| `docs/te/00-phase-0-setup.md` | Phase 0 explained in Telugu |
| `docs/te/06-phase-1-app-source.md` | Phase 1 app source, Dockerfiles, local smoke test |
| `docs/te/01-architecture-telugu.md` | Architecture in Telugu |
| `docs/te/02-issues-guide-telugu.md` | Issue logging guide in Telugu |
| `docs/te/00-project-overview.md` | Telugu project overview |

## 5. Golden rules

1. Never commit secrets — External Secrets + IRSA only.
2. Every workload: requests, limits, probes, PDB, NetworkPolicy, own ServiceAccount.
3. Every real failure is logged in `docs/ISSUES.md` with a "why this only works" section.
4. Destroy cloud resources after each session.
5. Every created file gets a companion Telugu explanation in `docs/te/`.

## 6. Cost warning

EKS is **not free-tier**: control plane is ~$73/month. The lab is tuned to ~$85/month
if left running, or ~$5–8 per weekend session if destroyed. See
`docs/ARCHITECTURE.md` §8 and set AWS Budget alarms before Phase 2.

---

## తెలుగు సారాంశం

- **RetailX** — AWS EKS పై నిజమైన ఎంటర్‌ప్రైజ్ స్థాయి ఈ-కామర్స్ ప్రాజెక్ట్.
- Cilium (kube-proxy replacement), Gateway API, IRSA, External Secrets, RBAC, PSS, HPA, PDB — అన్నీ వాడుతాం.
- **EKS ఉచితం కాదు**; ప్రతి సెషన్ తర్వాత destroy చేయాలి (సెషన్‌కు ~$5–8).
- పాత Day 1/Day 2 ఫైల్స్ తొలగించబడ్డాయి; అవసరమైతే Git history నుండి తిరిగి పొందవచ్చు.
- ప్రతి ఫైల్ వివరణ `docs/te/` లో; ప్రతి సమస్య `docs/ISSUES.md` లో నమోదు.
- సీక్రెట్స్ Git లో పెట్టకూడదు; probes, limits, PDB, NetworkPolicy తప్పనిసరి.
