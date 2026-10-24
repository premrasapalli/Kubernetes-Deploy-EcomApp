# ── తెలుగు వివరణ ─────────────────────────────────────────────
# EKS క్లస్టర్. ముఖ్యాంశాలు:
# 1) module v21 `bootstrap_self_managed_addons` ను hardcode గా false చేస్తుంది
#    → aws-node/kube-proxy ఇన్‌స్టాల్ అవ్వవు.
# 2) addons లో coredns మాత్రమే → Cilium నే CNI + kube-proxy replacement.
# 3) Node group desired=0 తో మొదటి apply; Cilium తర్వాత desired=2 (2-stage).
#    ఎందుకంటే CNI లేకుండా nodes NotReady అవుతాయి (Issue #1 చూడండి).
# ─────────────────────────────────────────────────────────────
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.cluster_version

  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  enable_cluster_creator_admin_permissions = true

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  addons = var.install_addons ? {
    coredns = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = aws_iam_role.ebs_csi.arn
    }
  } : {}

  eks_managed_node_groups = {
    default = {
      name           = "${var.project}-ng"
      instance_types = var.node_instance_types
      capacity_type  = "SPOT"

      min_size     = 0
      desired_size = var.node_desired_size
      max_size     = var.node_max_size

      subnet_ids = module.vpc.private_subnets
      ami_type   = "AL2023_x86_64_STANDARD"
      disk_size  = 30

      labels = {
        role = "general"
      }

      update_config = {
        max_unavailable_percentage = 33
      }
    }
  }

  node_security_group_additional_rules = {
    ingress_self_cilium_vxlan = {
      description = "Cilium VXLAN node-to-node"
      protocol    = "udp"
      from_port   = 8472
      to_port     = 8472
      type        = "ingress"
      self        = true
    }
    ingress_self_cilium_health = {
      description = "Cilium health checks node-to-node"
      protocol    = "tcp"
      from_port   = 4240
      to_port     = 4240
      type        = "ingress"
      self        = true
    }
  }

  tags = local.tags
}
