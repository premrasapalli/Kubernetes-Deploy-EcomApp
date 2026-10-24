# ── తెలుగు వివరణ ─────────────────────────────────────────────
# డేటాబేస్ పాస్‌వర్డ్ మరియు JWT సీక్రెట్ random గా generate అయి AWS Secrets Manager లో
# నిల్వ ఉంటాయి. Git లో ఎప్పుడూ సీక్రెట్ ఉండదు. External Secrets Operator వాటిని
# K8s Secret గా sync చేస్తుంది. recovery_window_in_days=0 → destroy వెంటనే పూర్తి.
# ─────────────────────────────────────────────────────────────
resource "random_password" "postgres" {
  length  = 24
  special = false
}

resource "aws_secretsmanager_secret" "postgres" {
  name                    = "${var.project}/postgres"
  description             = "RetailX PostgreSQL credentials"
  recovery_window_in_days = 0
  tags                    = local.tags
}

resource "aws_secretsmanager_secret_version" "postgres" {
  secret_id = aws_secretsmanager_secret.postgres.id
  secret_string = jsonencode({
    username = "retailx"
    password = random_password.postgres.result
  })
}

resource "random_password" "jwt" {
  length  = 48
  special = false
}

resource "aws_secretsmanager_secret" "jwt" {
  name                    = "${var.project}/jwt"
  description             = "RetailX JWT signing secret"
  recovery_window_in_days = 0
  tags                    = local.tags
}

resource "aws_secretsmanager_secret_version" "jwt" {
  secret_id = aws_secretsmanager_secret.jwt.id
  secret_string = jsonencode({
    jwt_secret = random_password.jwt.result
  })
}
