# ── తెలుగు వివరణ ─────────────────────────────────────────────
# VPC: 2 AZలు, public + private subnets. Nodes private లో ఉంటాయి (enterprise).
# ఖర్చు తగ్గించడానికి single NAT Gateway (prod లో per-AZ NAT).
# Private subnet CIDR: 10.0.11.0/24, 10.0.12.0/24.
# Gateway VIP 10.0.11.250 ఈ private subnet లో ఉంటుంది.
# ─────────────────────────────────────────────────────────────
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project}-vpc"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  private_subnets = ["10.0.11.0/24", "10.0.12.0/24"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  enable_dns_hostnames = true
  enable_dns_support   = true

  map_public_ip_on_launch = false

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  tags = local.tags
}
