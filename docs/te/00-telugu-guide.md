# [TELUGU EXPLANATION]
# PURPOSE      : ఈ project మొత్తం Telugu లో roadmap + learning path
# WHAT IT DOES : Step by step guide, mindset, how to think enterprise style
# WHY ENTERPRISE: నేర్చుకునే విధానాన్ని enterprise లాగా మార్చడానికి
# HOW TO USE   : ప్రతీ రోజు start చేసినప్పుడు ఈ doc చదివి proceed చేయి
# NOTES        : "మాట్లాడడం కంటే చేయడం" - Build -> Break -> Fix -> Document

# TELUGU_GUIDE.md - retailx నేర్చుకునే మార్గదర్శిని (Telugu)

## 1) ఈ project ఎందుకు?

మీరు EKS + Cilium + Gateway API + Security + Troubleshooting అన్నీ **zero నుండి build చేస్తూ** నేర్చుకోవాలి అనేది ఈ project లక్ష్యం.

ఇది tutorial copy-paste కాదు. **Design -> Implement -> Break -> Fix -> Document**.

## 2) Mindset (అతి ముఖ్యమైనది)
| Mindset | వివరణ (Telugu) |
| --- | --- |
| **Curiosity** | Error వచ్చినప్పుడు "ఎందుకు?" అని అడగాలి |
| **Root Cause First** | Symptom fix కాకుండా Root Cause కనుక్కోవాలి |
| **Why-only-this-works** | ప్రతి fix కి "ఇదే ఎందుకు మాత్రమే పని చేస్తుంది?" explain చేయగలగాలి |
| **Cost Aware** | Free Tier లో ఎంత minimal గా build చేయవచ్చో ఆలోచించాలి |
| **Enterprise Thinking** | "ఇది prod లో ఎలా వుండేది?" అని self-question వేసుకోవాలి |
| **Document or Forget** | Issue వస్తే `ISSUES.md` లో log చేయకుండా ముందుకు వెళ్లకూడదు |

## 3) Roadmap (Phases)
| Phase | Name | Goal (Telugu) | Status |
| --- | --- | --- | --- |
| **Phase 0** | Workspace Scaffolding | Folders, Docs, Templates, Telugu rules setup | **DONE** |
| **Phase 1** | App From Scratch | Microservices (frontend/product-api/cart-api/order-api) + Dockerfiles + build script | **DONE** |
| **Phase 2** | Terraform EKS | VPC, Private/Public, NAT(1), EKS, IRSA, ECR, NodeGroup(2× t3.medium spot) | **IN PROGRESS** |
| **Phase 3** | Bootstrap Platform | Cilium(KPR, IPAM=kubernetes), Gateway API, LB IPAM, Hubble, ESO, metrics-server | **IN PROGRESS** |
| **Phase 4** | K8s Manifests Enterprise Style | NS, SA+RBAC, PSS, NetPol/CiliumNetPol, Workloads, Probes, Resources, PDB, HPA, TSC, ExternalSecrets | **DONE (pre-apply)** |
| **Phase 5** | Wire & Validate | Gateway/HTTPRoute, E2E test, L7 policy, Hubble flows verify | **IN PROGRESS** |
| **Phase 6** | Break-Fix + Harden | Intentional issues create చేసి fix + `ISSUES.md` strict log | PENDING |
| **Phase 7** | Teardown/Practice | Destroy-Rebuild multiple times till you can explain every file | PENDING |

## 4) Folder Wise Learning Focus
| Folder | Focus (Telugu) | Priority |
| --- | --- | --- |
| `docs/` | Architecture, Issues, Runbook, Cost, Telugu Guide | **CRITICAL** |
| `01-terraform-eks/` | Networking, EKS, IRSA - AWS + K8s linkage | **CRITICAL** |
| `02-app-source/` | App logic + Docker best practices (multi-stage later) | HIGH |
| `03-k8s-manifests/` | Enterprise K8s objects, security, resiliency | **CRITICAL** |
| `04-platform/` | Cilium deep, Gateway API, ESO, Observability | **CRITICAL** |
| `05-scripts/` | Automation & safe teardown | HIGH |

## 4.1) Phase-wise Telugu docs
| Doc | Contents |
| --- | --- |
| `docs/te/06-phase-1-app-source.md` | App source, Dockerfiles, local compose smoke test |
| `docs/te/07-phase-2-terraform.md` | Terraform files ఒక్కొక్కటి + Issue #1 |
| `docs/te/08-phase-3-platform.md` | Cilium values, Gateway API, LB IPAM, ESO |
| `docs/te/09-phase-4-manifests.md` | Manifests, PSS, CiliumNetworkPolicy, probes |
| `docs/te/10-phase-5-deploy.md` | Provision/build/deploy/validate/teardown |
| `docs/te/issues/` | ప్రతి నిజమైన issue కి Telugu వివరణ |

## 5) Practical Tips (Telugu)
- **File by File** - ఒక్కో file create చేసిన తర్వాత దాని `[TELUGU EXPLANATION]` block చదువు
- **Explain to Mirror** - Create చేసిన ప్రతి manifest ని నీవే "ఇది ఎందుకు?" అని అడిగి సమాధానం చెప్పుకో
- **Break to Learn** - Clumsy గా కాకుండా thought-out break చేసి fix చేయి
- **Hubble Habit** - Traffic flows చూడటానికి `hubble observe` అలవాటు చేయి
- **Free Tier Discipline** - Session ముగిసే ముందు Cost Awareness check
- **Issue Driven** - Error వస్తే వెంటనే `ISSUES.md` లో log
- **Telugu Notes** - `LEARNINGS.md` లో రోజూ రాయడం అలవాటు

## 6) Mandatory Checklist for Issue Logging
`ISSUES.md` fill చేస్తున్నప్పుడు కింది checkboxes పాటించాలి
- [ ] Environment details fill చేశాను
- [ ] Issue clearly describe చేశాను (error/logs)
- [tag] Root Cause సాంకేతికంగా రాశాను
- [ ] Investigation cmds + findings రాశాను
- [ ] Resolution exact step by step రాశాను
- [ ] **Why this only works** ని enterprise angle తో రాశాను
- [ ] Verification proof ఇచ్చాను
- [ ] Prevention & Cost Impact రాశాను

## 7) Next Step
**Phase 0 పూర్తయ్యాక** - `START PHASE 1` అని టైప్ చేయి.

Phase 1 లో మనం **retailx app source code** (frontend, product-api, cart-api, order-api) zero నుండి create చేస్తాము.

**Goal:** "AWS EKSపై Enterprise K8s ని నేర్పడం కాదు - నీవే ఒకవేళ model/master కావడానికి నేర్పడం".
