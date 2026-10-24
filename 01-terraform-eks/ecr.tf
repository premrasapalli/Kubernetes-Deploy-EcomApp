# ── తెలుగు వివరణ ─────────────────────────────────────────────
# ప్రతి మైక్రోసర్వీస్‌కు ఒక ECR రిపోజిటరీ. scan_on_push=true → ఇమేజ్ పుష్ అయ్యాక
# vulnerability scan. force_delete=true → teardown సులభం (ఇమేజ్‌లు ఉన్నా delete).
# ─────────────────────────────────────────────────────────────
locals {
  services = ["frontend", "product-api", "cart-api", "order-api"]
}

resource "aws_ecr_repository" "app" {
  for_each = toset(local.services)

  name                 = "${var.project}/${each.key}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  force_delete = true

  tags = local.tags
}

resource "aws_ecr_lifecycle_policy" "app" {
  for_each   = aws_ecr_repository.app
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
