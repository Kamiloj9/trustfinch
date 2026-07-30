resource "aws_dynamodb_table" "this" {
  name         = "${var.name}-gitlab-oidc-replay"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "jti"

  attribute {
    name = "jti"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = merge(var.tags, { Name = "${var.name}-gitlab-oidc-replay" })
}

data "aws_iam_policy_document" "runtime" {
  statement {
    sid       = "ConsumeGitLabOIDCTokensOnce"
    effect    = "Allow"
    actions   = ["dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [aws_dynamodb_table.this.arn]
  }
}

resource "aws_iam_role_policy" "runtime" {
  name   = "gitlab-oidc-replay-protection"
  role   = var.runtime_role_name
  policy = data.aws_iam_policy_document.runtime.json
}
