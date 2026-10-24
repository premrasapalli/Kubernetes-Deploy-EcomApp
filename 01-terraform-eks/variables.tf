# ── తెలుగు వివరణ ─────────────────────────────────────────────
# అన్ని మార్చగల విలువలు ఇక్కడ. డిఫాల్ట్‌లు ల్యాబ్ (ఖర్చు తక్కువ) కి సరిపోతాయి.
# ─────────────────────────────────────────────────────────────
variable "project" {
  description = "Resource name prefix"
  type        = string
  default     = "retailx"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "retailx-eks"
}

variable "cluster_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.36"
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint (restrict in prod)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_instance_types" {
  description = "Node instance types (SPOT)"
  type        = list(string)
  default     = ["t3.medium", "t3a.medium"]
}

variable "node_desired_size" {
  description = "Desired node count (0 during CNI bootstrap, then 2)"
  type        = number
  default     = 2
}

variable "install_addons" {
  description = "Install EKS addons (set true only after nodes + CNI ready)"
  type        = bool
  default     = false
}

variable "node_max_size" {
  description = "Maximum node count"
  type        = number
  default     = 3
}

variable "gateway_ip" {
  description = "Gateway VIP allocated by Cilium LB IPAM (must be free in a private subnet)"
  type        = string
  default     = "10.0.11.250"
}
