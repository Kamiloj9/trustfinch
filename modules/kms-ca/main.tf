data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "root" {
  statement {
    sid    = "EnableAccountIAMControl"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "KeyAdministrationWithoutCryptographicUse"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = var.key_administrator_arns
    }

    actions = [
      "kms:Create*", "kms:Describe*", "kms:Enable*", "kms:Disable*", "kms:Get*",
      "kms:List*", "kms:Put*", "kms:Revoke*", "kms:Update*", "kms:TagResource",
      "kms:UntagResource", "kms:ScheduleKeyDeletion", "kms:CancelKeyDeletion"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "RootCeremonyReadPublicKey"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = var.root_ceremony_role_arns
    }

    actions   = ["kms:GetPublicKey"]
    resources = ["*"]
  }

  statement {
    sid    = "RootCeremonySigningOnly"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = var.root_ceremony_role_arns
    }

    actions   = ["kms:Sign"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:SigningAlgorithm"
      values   = ["ECDSA_SHA_256"]
    }
  }
}

data "aws_iam_policy_document" "intermediate" {
  statement {
    sid    = "EnableAccountIAMControl"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "KeyAdministrationWithoutCryptographicUse"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = var.key_administrator_arns
    }

    actions = [
      "kms:Create*", "kms:Describe*", "kms:Enable*", "kms:Disable*", "kms:Get*",
      "kms:List*", "kms:Put*", "kms:Revoke*", "kms:Update*", "kms:TagResource",
      "kms:UntagResource", "kms:ScheduleKeyDeletion", "kms:CancelKeyDeletion"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "RuntimeReadIntermediatePublicKey"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [var.runtime_role_arn]
    }

    actions   = ["kms:GetPublicKey"]
    resources = ["*"]
  }

  statement {
    sid    = "RuntimeCanSignOnlyWithIntermediate"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [var.runtime_role_arn]
    }

    actions   = ["kms:Sign"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:SigningAlgorithm"
      values   = ["ECDSA_SHA_256"]
    }
  }

  dynamic "statement" {
    for_each = length(var.intermediate_ceremony_role_arns) == 0 ? [] : [1]

    content {
      sid    = "CeremonyMayReadIntermediatePublicKey"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = var.intermediate_ceremony_role_arns
      }

      actions   = ["kms:GetPublicKey"]
      resources = ["*"]
    }
  }
}

resource "aws_kms_key" "root" {
  description              = "${var.name} offline-logical root CA signing key"
  customer_master_key_spec = "ECC_NIST_P256"
  key_usage                = "SIGN_VERIFY"
  is_enabled               = var.root_key_enabled
  deletion_window_in_days  = var.deletion_window_in_days
  policy                   = data.aws_iam_policy_document.root.json

  tags = merge(var.tags, {
    Name      = "${var.name}-root-ca"
    PKIRole   = "root"
    Protected = "true"
  })
}

resource "aws_kms_alias" "root" {
  name          = "alias/${var.name}-root-ca"
  target_key_id = aws_kms_key.root.key_id
}

resource "aws_kms_key" "intermediate" {
  description              = "${var.name} online intermediate CA signing key"
  customer_master_key_spec = "ECC_NIST_P256"
  key_usage                = "SIGN_VERIFY"
  deletion_window_in_days  = var.deletion_window_in_days
  policy                   = data.aws_iam_policy_document.intermediate.json

  tags = merge(var.tags, {
    Name      = "${var.name}-intermediate-ca"
    PKIRole   = "intermediate"
    Protected = "true"
  })
}

resource "aws_kms_alias" "intermediate" {
  name          = "alias/${var.name}-intermediate-ca"
  target_key_id = aws_kms_key.intermediate.key_id
}
