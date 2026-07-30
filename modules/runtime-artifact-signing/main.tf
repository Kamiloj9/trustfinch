data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "this" {
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
    sid    = "KeyAdministrationWithoutSigning"
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
    sid    = "ApprovedReleaseSignersOnly"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = var.artifact_signer_role_arns
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

resource "aws_kms_key" "this" {
  description              = "${var.name} runtime-artifact manifest signing key"
  customer_master_key_spec = "ECC_NIST_P256"
  key_usage                = "SIGN_VERIFY"
  deletion_window_in_days  = var.deletion_window_in_days
  policy                   = data.aws_iam_policy_document.this.json

  lifecycle {
    precondition {
      condition     = length(setintersection(toset(var.key_administrator_arns), toset(var.artifact_signer_role_arns))) == 0
      error_message = "Artifact signing roles must be distinct from KMS key administrator roles."
    }
  }

  tags = merge(var.tags, {
    Name      = "${var.name}-runtime-artifact-signing"
    PKIRole   = "runtime-artifact-signing"
    Protected = "true"
  })
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.name}-runtime-artifact-signing"
  target_key_id = aws_kms_key.this.key_id
}

data "aws_kms_public_key" "this" {
  key_id = aws_kms_key.this.key_id
}
