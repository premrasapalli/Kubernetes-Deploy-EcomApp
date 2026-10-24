# [TELUGU EXPLANATION]
# PURPOSE      : retailx-enterprise-k8s ప్రాజెక్ట్ యొక్క root README
# WHAT IT DOES : ఈ ప్రాజెక్ట్ గురించి συνοక్షిప్త అవగాహన ఇస్తుంది
# WHY ENTERPRISE: enterprise mindset తో ఎలా నేర్చుకోవాలో చూపిస్తుంది
# HOW TO USE   : కొత్తవారు కూడా ఈ README ద్వారా start చేయవచ్చు
# NOTES        : ప్రతి step లో Telugu explanation follow అవ్వాలి

# retailx-enterprise-k8s

> **Goal:** AWS EKS పై Zero నుండి Enterprise-level Kubernetes Project Build చేయడం (Build -> Break -> Fix -> Document)

## ఎందుకు ఈ ప్రాజెక్ట్?

ఈ ప్రాజెక్ట్ లక్ష్యం - AWS EKS ఉపయోగించి నిజమైన enterprise environment లాగా Kubernetes ని design చేయడం, build చేయడం, troubleshoot చేయడం నేర్చుకోవడం.

మనం app కూడా zero నుండి create చేస్తాము, IaC నుంచీ platform వరకు అన్నీ మనమే build చేస్తాము.

## Project Name
**retailx** - ఒక fake e-commerce app (Product, Cart, Order, Frontend + Postgres + Redis)

## Core Principles
- **Learn by Doing** - కేవలం read చేయడం కాకుండా build చేస్తూ నేర్చుకుంటాము
- **Telugu First** - ప్రతి file కి Telugu explanation ఉంటుంది
- **Cost Aware (Free Tier)** - AWS Free Tier ని గుర్తుంచుకొని minimal resources వాడతాము
- **Enterprise Style** - IRSA, PSS Restricted, CiliumNetworkPolicy, Gateway API, External Secrets లాంటి реальные technieken
- **Document Everything** - ప్రతీ issue ని `00-docs/ISSUES.md` లో log చేస్తాము

## Folder Structure
| Folder | Purpose |
| --- | --- |
| `00-docs/` | Architecture, Issues, Learnings, Runbook, Cost Awareness, Telugu Guide |
| `01-terraform-eks/` | EKS + VPC + IRSA + ECR create చేయడానికి Terraform |
| `02-app-source/` | Microservices source code (frontend, product-api, cart-api, order-api) + Dockerfiles |
| `03-k8s-manifests/` | K8s YAMLs (base/overlays with Kustomize) - Namespaces, RBAC, Workloads, NetworkPolicies etc |
| `04-platform/` | Platform components - Cilium, Gateway API, External Secrets, kube-prometheus-stack |
| `05-scripts/` | bootstrap.sh, validate.sh, teardown.sh లాంటి automation scripts |

## Rules
1. **ప్రతి file కి Telugu Explanation block తప్పనిసరి**
2. **AWS Free Tier ని దృష్టిలో పెట్టుకొని build చేయాలి**
3. **ప్రతి issue ని `00-docs/ISSUES.md` లో strict format లో log చేయాలి**
4. **Secrets ఎప్పుడూ Git లో commit చేయకూడదు** (External Secrets + AWS Secrets Manager)
5. **Build -> Break -> Fix -> Document** మాత్రమే

## Quick Start
మనం Phase 0 నుండి start చేసి step by step వెళ్లాలి.

అన్ని phases, order, ఎలా proceed అవ్వాలో `00-docs/TELUGU_GUIDE.md` చూడండి.

## Current Status
- [x] Phase 0: Workspace Scaffolding
- [x] Phase 1: App From Scratch (`docs/te/06-phase-1-app-source.md`)
- [ ] Phase 2: Terraform EKS
- [ ] Phase 3: Bootstrap Platform
- [ ] Phase 4: K8s Manifests (Enterprise Style)
- [ ] Phase 5: Wire & Validate
- [ ] Phase 6: Break-Fix + Harden
- [ ] Phase 7: Teardown/Practice

**IMPORTANT:** ఈ ప్రాజెక్ట్ పూర్తిగా learning purpose కోసం. AWS Free Tier లో run చేస్తున్నాము కాబట్టి తప్పకుండా `00-docs/COST_AWARENESS.md` follow అవ్వండి.
