# [TELUGU EXPLANATION]
# PURPOSE      : 01-terraform-eks folder యొక్క purpose & usage
# WHAT IT DOES : Terraform modules/layout గురించి వివరణ
# WHY ENTERPRISE: IaC structure enterprise లాగా ఉంటుంది
# HOW TO USE   : Phase 2 లో fill చేయడం
# NOTES        : AWS Free-Tier mindful (t3.small, 1 NAT)

# 01-terraform-eks/README.md

## Folder Purpose (లక్ష్యం)
ఈ folder లో **AWS EKS cluster** ని create చేయడానికి కావలసిన Terraform code ఉంచుతాము.

VPC, Subnets, NAT Gateway(1), EKS Cluster, Managed NodeGroup, IRSA, ECR రెస్పాన్సివ్గా ఇక్కడ నుంచే create చేస్తాము.

## What will be created (ఏమేమి వస్తాయి)
| Resource | Purpose (Telugu) |
| --- | --- |
| **VPC** | Custom VPC (private/public subnets) |
| **NAT Gateway** | Private subnets నుండి outbound internet (single NAT - cost aware) |
| **EKS Cluster** | Control plane (K8s 1.36) |
| **Managed NodeGroup** | Worker nodes (t3.small, min 1) |
| **IAM Roles/Policies** | Cluster/Node roles + IRSA foundation |
| **ECR Repos** | retailx images store చేయడానికి |
| **Security Groups** | Tight SG rules |

## Files (Phase 2 లో create చేస్తాము)
| File | Purpose |
| --- | --- |
| `providers.tf` | AWS/Terraform provider config |
| `backend.tf` | State backend (local first, explain later) |
| `variables.tf` | All variables with descriptions |
| `vpc.tf` | VPC/Subnets/RouteTables/NAT |
| `eks.tf` | EKS Cluster + NodeGroup |
| `iam-irsa.tf` | IRSA roles/policies |
| `ecr.tf` | ECR repositories |
| `outputs.tf` | Useful outputs (cluster name, endpoint) |

## Enterprise Notes (Telugu)
- **Private-first mindset** - Nodes private subnets లో పెట్టాము
- **Minimal NAT** - 1 NAT Gateway (Free-Tier conscious)
- **IRSA** - Pod level IAM permissions
- **Managed NodeGroup** - Enterprise friendly

## Usage
```bash
# Phase 2 లో మాత్రమే run చేయాలి
terraform init
terraform plan
terraform apply
```

**Rule:** ప్రతి `.tf` file top లో `[TELUGU EXPLANATION]` block + inline Telugu comments తప్పనిసరిగా వుంటాయి.
