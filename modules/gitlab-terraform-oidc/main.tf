locals {
  oidc_claim_namespace = trimprefix(var.oidc_provider_url, "https://")
}

data "aws_iam_policy_document" "plan_assume" {
  statement {
    sid     = "AllowGitLabOIDCPlan"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_claim_namespace}:aud"
      values   = [var.audience]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_claim_namespace}:sub"
      values   = var.plan_subjects
    }

    dynamic "condition" {
      for_each = var.plan_additional_claims

      content {
        test     = "StringEquals"
        variable = "${local.oidc_claim_namespace}:${condition.key}"
        values   = condition.value
      }
    }
  }
}

data "aws_iam_policy_document" "apply_assume" {
  statement {
    sid     = "AllowGitLabOIDCApply"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_claim_namespace}:aud"
      values   = [var.audience]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_claim_namespace}:sub"
      values   = var.apply_subjects
    }

    dynamic "condition" {
      for_each = var.apply_additional_claims

      content {
        test     = "StringEquals"
        variable = "${local.oidc_claim_namespace}:${condition.key}"
        values   = condition.value
      }
    }
  }
}

resource "aws_iam_role" "plan" {
  name                 = "${var.name}-gitlab-terraform-plan"
  description          = "GitLab OIDC Terraform plan role for ${var.name}."
  assume_role_policy   = data.aws_iam_policy_document.plan_assume.json
  max_session_duration = 3600
  permissions_boundary = var.permissions_boundary_arn

  lifecycle {
    precondition {
      condition     = endswith(var.oidc_provider_arn, "oidc-provider/${local.oidc_claim_namespace}")
      error_message = "oidc_provider_arn must identify the same issuer as oidc_provider_url."
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name}-gitlab-terraform-plan"
    Role = "terraform-plan"
  })
}

resource "aws_iam_role" "apply" {
  name                 = "${var.name}-gitlab-terraform-apply"
  description          = "GitLab OIDC Terraform apply role for ${var.name}."
  assume_role_policy   = data.aws_iam_policy_document.apply_assume.json
  max_session_duration = 3600
  permissions_boundary = var.permissions_boundary_arn

  tags = merge(var.tags, {
    Name = "${var.name}-gitlab-terraform-apply"
    Role = "terraform-apply"
  })
}

resource "aws_iam_role_policy_attachment" "plan" {
  for_each = toset(var.plan_policy_arns)

  role       = aws_iam_role.plan.name
  policy_arn = each.value
}

resource "aws_iam_role_policy_attachment" "apply" {
  for_each = toset(var.apply_policy_arns)

  role       = aws_iam_role.apply.name
  policy_arn = each.value
}
