# ── తెలుగు వివరణ ─────────────────────────────────────────────
# IRSA = IAM Roles for Service Accounts. Pod కి AWS అనుమతులు, node కి కాదు.
# ఇక్కడ External Secrets Operator (namespace platform, SA external-secrets) కి
# Secrets Manager చదివే అనుమతి మాత్రమే ఇస్తున్నాం — least privilege.
# Trust policy లో OIDC provider + exact namespace/SA condition ఉండాలి.
# ─────────────────────────────────────────────────────────────
data "aws_iam_policy_document" "eso_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:platform:external-secrets"]
    }
  }
}

resource "aws_iam_role" "eso" {
  name               = "${var.project}-eso"
  assume_role_policy = data.aws_iam_policy_document.eso_assume_role.json
  tags               = local.tags
}

data "aws_iam_policy_document" "eso_permissions" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [
      "arn:aws:secretsmanager:${local.region}:${local.account_id}:secret:${var.project}/*",
    ]
  }
}

resource "aws_iam_role_policy" "eso" {
  name   = "${var.project}-eso-secrets"
  role   = aws_iam_role.eso.id
  policy = data.aws_iam_policy_document.eso_permissions.json
}

# ── తెలుగు వివరణ ─────────────────────────────────────────────
# EBS CSI driver కి IRSA. ఇది PVC కోసం EBS వాల్యూమ్‌లు సృష్టించడానికి కావాలి.
# లేకపోతే postgres/redis PVCలు Pending లో ఉంటాయి (Issue #3 చూడండి).
# ─────────────────────────────────────────────────────────────
data "aws_iam_policy_document" "ebs_csi_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.project}-ebs-csi"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}
