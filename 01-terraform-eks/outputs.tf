# ── తెలుగు వివరణ ─────────────────────────────────────────────
# తర్వాత scripts కి కావాల్సిన విలువలు. `terraform output` తో తీసుకోవచ్చు.
# ─────────────────────────────────────────────────────────────
output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "region" {
  value = local.region
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnets" {
  value = module.vpc.private_subnets
}

output "gateway_ip" {
  value = var.gateway_ip
}

output "ecr_registry" {
  value = "${local.account_id}.dkr.ecr.${local.region}.amazonaws.com"
}

output "ecr_repositories" {
  value = { for k, v in aws_ecr_repository.app : k => v.repository_url }
}

output "eso_role_arn" {
  value = aws_iam_role.eso.arn
}

output "ebs_csi_role_arn" {
  value = aws_iam_role.ebs_csi.arn
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}
