# Phase 2 — Terraform (VPC + EKS + ECR + IRSA + Secrets)

> ఇంగ్లీష్ సారాంశం: `docs/ARCHITECTURE.md` Section 11, `docs/ISSUES.md` Issue #1.

## ఫైల్‌లు ఒక్కొక్కటి

### `01-terraform-eks/versions.tf`
- `terraform.required_version >= 1.6` — `terraform` కనీస వెర్షన్.
- `aws ~> 6.0`, `random ~> 3.6` — provider వెర్షన్లు.
- **ఎందుకు:** వెర్షన్ పరిధి లేకపోతే CI లో ఏదో ఒకరోజు incompatible provider వచ్చి
  అన్నీ పగిలిపోతాయి.

### `providers.tf`
- `provider "aws" { region = var.region }` + `default_tags` (`Project = retailx`).
- **ఎందుకు:** ట్యాగ్‌లు ఖర్చు రిపోర్ట్‌లలో, `aws resourcegroupstaggingapi` లో ఉపయోగం.

### `variables.tf`
- `cluster_name`, `cluster_version = "1.36"`, `region = "us-east-1"`.
- `vpc_cidr`, `node_instance_types = ["t3.medium"]`, `node_desired_size = 2`.
- `cluster_endpoint_public_access_cidrs` — మీ IP కి మాత్రమే API access.
- **గమనిక:** `node_desired_size` ను `-var` తో 0/2 మార్చడమే two-stage bootstrap కి కీలకం.

### `vpc.tf`
- `terraform-aws-modules/vpc/aws` `5.21.0`.
- `10.0.0.0/16`; private `10.0.11.0/24`, `10.0.12.0/24`; public `10.0.1.0/24`, `10.0.2.0/24`.
- `enable_nat_gateway = true`, `single_nat_gateway = true` — ఖర్చు తగ్గించడానికి 1 NAT.
- `enable_dns_hostnames/handles = true` — EKS కి తప్పనిసరి.
- `private_subnet_tags` లో `kubernetes.io/role/internal-elb`, `karpenter.sh/discovery`.
- **ఎందుకు private:** nodes కి public IP ఇవ్వము; egress NAT ద్వారా (image pull, AWS API).

### `eks.tf`
- `terraform-aws-modules/eks/aws` `~> 21.0` (lock 21.29.0).
- `name`, `kubernetes_version` — v21 పేర్లు (Issue #1).
- `endpoint_public_access = true`, CIDR restriction తో.
- `enable_cluster_creator_admin_permissions = true`.
- `addons`: `coredns` (most_recent), `aws-ebs-csi-driver` + IRSA role.
- `eks_managed_node_groups.default`:
  - `instance_types = ["t3.medium"]`, `capacity_type = "SPOT"`, `desired_size = var.node_desired_size`.
  - `min_size = 0`, `max_size = 3`.
  - `subnet_ids = module.vpc.private_subnets`.
  - `iam_role_additional_policies = { AmazonSSMManagedInstanceCore = ... }` — SSM debug కి.
- **ఎందుకు `bootstrap_self_managed_addons` ఇవ్వలేదు:** v21 దానిని hardcode `false`
  చేస్తుంది → `aws-node` రాదు → Cilium native CNI.

### `irsa.tf`
- `aws_iam_role.ebs_csi` — trust policy OIDC `system:serviceaccount:kube-system:ebs-csi-controller-sa`.
- `aws_iam_role.eso` — trust policy `system:serviceaccount:platform:external-secrets`.
- `aws_iam_policy.eso` — Secrets Manager `GetSecretValue/DescribeSecret` `retailx/*` కి మాత్రమే.
- **ఎందుకు IRSA:** node role కి Secrets Manager permissions ఇస్తే ఆ node లోని ఏ pod అయినా
  secrets చదవగలదు. SA-స్థాయి అనుమతి least privilege.

### `ecr.tf`
- 4 repositories: `retailx/frontend`, `product-api`, `cart-api`, `order-api`.
- `image_tag_mutability = "IMMUTABLE"`, `scan_on_push = true`, `force_delete = true`.
- Lifecycle policy: చివరి 10 ఇమేజ్‌లు మాత్రమే — storage ఖర్చు నియంత్రణ.
- **ఎందుకు IMMUTABLE:** `v1` ట్యాగ్ ను మళ్లీ push చేయలేరు → ఏ node ఏ కోడ్ నడుపుతుందో స్పష్టం.

### `secrets.tf`
- `random_password.postgres` (24), `random_password.jwt` (48).
- `aws_secretsmanager_secret` — `retailx/postgres`, `retailx/jwt`, `recovery_window_in_days = 0`.
- JSON secret string: username/password/host/port/db.
- **ఎందుకు `recovery_window=0`:** destroy తర్వాత మళ్లీ అదే పేరుతో సృష్టించగలగాలి.

### `outputs.tf`
- `cluster_name`, `cluster_endpoint`, `ecr_registry`, `eso_role_arn`, `gateway_ip`, `vpc_id`, `private_subnets`.
- స్క్రిప్ట్‌లు `terraform output -raw ...` తో వాడతాయి.

### `terraform.tfvars.example`
- కాపీ చేసి `terraform.tfvars` చేయండి; `cluster_endpoint_public_access_cidrs` లో మీ IP.
- `terraform.tfvars` Git లో పెట్టకూడదు (`.gitignore` లో ఉంది).

## ఇక్కడ నేర్చుకున్న పొరపాటు
Issue #1: module `~> 21.0` → 21.29.0, `cluster_*` inputs mute అయ్యాయి,
`bootstrap_self_managed_addons` తీసేశారు. వివరాలు `docs/te/issues/01-eks-module-v21-inputs.md`.

## ధృవీకరణ
```bash
cd 01-terraform-eks
terraform init
terraform validate     # Success
terraform plan -var node_desired_size=0
```
