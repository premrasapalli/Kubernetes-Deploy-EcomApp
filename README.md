# Kubernetes-Deploy-EcomApp

Enterprise EKS + Kubernetes learning track — Ecommerce app (frontend, redis).

| Folder | Day | Contents |
|---|---|---|
| [`day1-terraform-eks/`](./day1-terraform-eks) | Day 1 — EKS cluster on AWS | Terraform: VPC, EKS, KMS, outputs + troubleshooting log |
| [`day2-k8s-workloads/`](./day2-k8s-workloads) | Day 2 — Core workloads & zero-downtime deploys | Frontend Deployment/Service/RBAC/PDB, Redis StatefulSet, gp3 StorageClass + troubleshooting log |

## Day 1 — Terraform EKS (`day1-terraform-eks/`)

Provisions the cluster used in Day 2:

- `providers.tf` — S3 backend + DynamoDB state lock, AWS provider
- `vpc.tf` — VPC module (private subnets, NAT gateways)
- `eks.tf` — EKS module v21 (cluster, addons, managed node group)
- `kms.tf` — KMS key for secrets encryption
- `variables.tf` / `outputs.tf`
- `troubleshoot.md` — Day 1 incident log (state locks, DNS outage, module v20→v21 migration, orphaned nodegroups)

```bash
cd day1-terraform-eks
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

## Day 2 — Kubernetes workloads (`day2-k8s-workloads/`)

App manifests deployed to the Day 1 cluster (namespace `ecommerce`):

```bash
kubectl apply -f gp3-storageclass.yaml
kubectl apply -f frontend-rbac.yaml        # ServiceAccount + Role + RoleBinding
kubectl apply -f frontend-deployment.yaml  # 3 replicas, maxUnavailable: 0
kubectl apply -f redis-statefulset.yaml    # StatefulSet + PVC (gp3)
kubectl apply -f service.yaml
kubectl apply -f pdb.yaml
```

| File | Purpose |
|---|---|
| `gp3-storageclass.yaml` | EBS CSI `gp3` StorageClass (default) |
| `frontend-rbac.yaml` | ServiceAccount, Role, RoleBinding (least privilege) |
| `frontend-deployment.yaml` | Stateless frontend, probes, topology spread, securityContext |
| `redis-statefulset.yaml` | Stateful redis with `volumeClaimTemplate` |
| `service.yaml` | ClusterIP service for the frontend |
| `pdb.yaml` | PodDisruptionBudget (`minAvailable: 2`) |
| `troubleshoot.md` | Day 2 debugging runbook (6 issues: PVC/gp3, rollout failures, ImagePullBackOff) |
