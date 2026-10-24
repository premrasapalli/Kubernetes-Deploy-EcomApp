# Issue #1 — Terraform EKS module v21.29 inputs మారాయి

> ఇంగ్లీష్ పూర్తి వివరణ: `docs/ISSUES.md` → Issue #1.
> ఇది నిజంగా వచ్చిన సమస్య; `terraform validate` లో కనిపించింది.

## 1. ఏం జరిగింది (Symptom)

`terraform validate` నడిపినప్పుడు:

```text
Error: Unsupported argument
  on eks.tf line 19, in module "eks":
  19:   bootstrap_self_managed_addons = false
An argument named "bootstrap_self_managed_addons" is not expected here.

Error: Unsupported argument
  on eks.tf line 25, in module "eks":
  25:   cluster_addons = { ... }
An argument named "cluster_addons" is not expected here.
```

అంటే మనం రాసిన పేర్లు ఆ మాడ్యూల్ వెర్షన్ కి తెలియవు.

## 2. అసలు కారణం (Root cause)

మనం `version = "~> 21.0"` అని ఇచ్చాం. దాని అర్థం "21.x లో ఏదైనా వెర్షన్".
Terraform **21.29.0** తీసుకుంది. ఆ వెర్షన్ లో input పేర్లు మారాయి:

| పాత పేరు | కొత్త పేరు (v21.29) |
|---|---|
| `cluster_name` | `name` |
| `cluster_version` | `kubernetes_version` |
| `cluster_endpoint_public_access` | `endpoint_public_access` |
| `cluster_endpoint_public_access_cidrs` | `endpoint_public_access_cidrs` |
| `cluster_addons` | `addons` |
| `bootstrap_self_managed_addons` | తీసేశారు — మాడ్యూల్ లోపల `false` hardcode |

`bootstrap_self_managed_addons = false` అనేది మనకు చాలా ముఖ్యం: అది
`aws-node` (VPC CNI) మరియు `kube-proxy` ను ఇన్‌స్టాల్ చేయకుండా ఆపుతుంది.
అప్పుడే Cilium పూర్తి నెట్‌వర్కింగ్ ను నిర్వహిస్తుంది. v21 మాడ్యూల్ దానిని
ఇప్పుడు తనే hardcode చేస్తుంది, కాబట్టి మనం ఇక ఇవ్వక్కర్లేదు.

## 3. ఎలా కనుగొన్నాం (Investigation)

```bash
cat .terraform/modules/modules.json          # Version: 21.29.0
grep '^variable' .terraform/modules/eks/variables.tf
# name, kubernetes_version, addons, endpoint_public_access ...
grep bootstrap_self_managed_addons .terraform/modules/eks/main.tf
# main.tf:46: bootstrap_self_managed_addons = false
```

## 4. పరిష్కారం (Resolution)

`01-terraform-eks/eks.tf` లో పేర్లు మార్చాం:

```hcl
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.cluster_version

  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  addons = {
    coredns            = { most_recent = true }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = aws_iam_role.ebs_csi.arn
    }
  }
}
```

`bootstrap_self_managed_addons` లైన్ తీసేశాం (ఇక అవసరం లేదు).

## 5. ఇది మాత్రమే ఎందుకు పనిచేస్తుంది (Why only this works)

- Terraform మాడ్యూల్ inputs ను **ఎంచుకున్న ఖచ్చితమైన వెర్షన్** తో పోలుస్తుంది.
- v21.29 లో పాత `cluster_*` పేర్లకు compatibility alias లేదు → పాత పేర్లు ఎప్పటికీ పనిచేయవు.
- `bootstrap_self_managed_addons` కు విలువ ఇవ్వడం కూడా పనిచేయదు; మాడ్యూల్ దానిని
  లోపలే `false` గా hardcode చేసింది.
- ఆ `false` వల్లనే `vpc-cni` రాదు → Cilium chaining mode లోకి వెళ్లదు → Gateway API పనిచేస్తుంది.

## 6. ధృవీకరణ (Verification)

```text
terraform validate  → Success! The configuration is valid.
terraform plan -var node_desired_size=0 → plan saved, errors లేవు
```

## 7. మళ్లీ రాకుండా (Prevention)

- మాడ్యూల్ వెర్షన్‌ను ఖచ్చితంగా pin చేయండి: `version = "= 21.29.0"`.
- వెర్షన్ పెంచే ముందు మాడ్యూల్ `docs/UPGRADE-*.md` చదవండి.
- CI లో ప్రతి మార్పుకు `terraform validate` నడపండి.
- `.terraform.lock.hcl` ను Git లో commit చేయండి.
