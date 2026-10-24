# ── తెలుగు వివరణ ─────────────────────────────────────────────
# AWS ప్రొవైడర్ మరియు ప్రాజెక్ట్ టాగ్లు. టాగ్లు వల్ల ఖర్చు ట్రాకింగ్,
# శుభ్రమైన teardown, మరియు ఏ రిసోర్స్ ఎవరిదో తెలుస్తుంది.
# ─────────────────────────────────────────────────────────────
provider "aws" {
  region = var.region

  default_tags {
    tags = local.tags
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Owner       = "retailx-platform"
  }
}
