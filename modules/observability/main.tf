data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_s3_bucket" "audit" {
  bucket_prefix = "${var.name}-pki-audit-"

  tags = merge(var.tags, {
    Name      = "${var.name}-pki-audit"
    DataClass = "security-audit"
  })
}

resource "aws_s3_bucket_public_access_block" "audit" {
  bucket                  = aws_s3_bucket.audit.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "audit" {
  bucket = aws_s3_bucket.audit.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "audit" {
  bucket = aws_s3_bucket.audit.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "audit_bucket" {
  statement {
    sid    = "CloudTrailGetBucketAcl"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.audit.arn]
  }

  statement {
    sid    = "CloudTrailWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.audit.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "audit" {
  bucket = aws_s3_bucket.audit.id
  policy = data.aws_iam_policy_document.audit_bucket.json
}

resource "aws_cloudwatch_log_group" "trail" {
  name              = "/pki/${var.name}/cloudtrail"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

data "aws_iam_policy_document" "cloudtrail_assume" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "cloudtrail" {
  name               = "${var.name}-cloudtrail-to-cloudwatch"
  assume_role_policy = data.aws_iam_policy_document.cloudtrail_assume.json

  tags = var.tags
}

data "aws_iam_policy_document" "cloudtrail_logs" {
  statement {
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.trail.arn}:log-stream:*"]
  }
}

resource "aws_iam_role_policy" "cloudtrail_logs" {
  name   = "cloudtrail-to-cloudwatch"
  role   = aws_iam_role.cloudtrail.name
  policy = data.aws_iam_policy_document.cloudtrail_logs.json
}

resource "aws_cloudtrail" "this" {
  name                          = "${var.name}-pki"
  s3_bucket_name                = aws_s3_bucket.audit.id
  include_global_service_events = true
  is_multi_region_trail         = false
  enable_log_file_validation    = true
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.trail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail.arn

  depends_on = [aws_s3_bucket_policy.audit]

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  tags = var.tags
}

resource "aws_cloudwatch_log_metric_filter" "root_sign" {
  name           = "${var.name}-root-kms-sign"
  log_group_name = aws_cloudwatch_log_group.trail.name
  pattern        = "{ ($.eventSource = \"kms.amazonaws.com\") && ($.eventName = \"Sign\") && ($.resources[0].ARN = \"${var.root_key_arn}\") }"

  metric_transformation {
    name      = "RootKmsSign"
    namespace = "PKI/${var.name}"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "root_sign" {
  alarm_name          = "${var.name}-root-kms-sign"
  alarm_description   = "Every root CA signing operation requires incident review."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = aws_cloudwatch_log_metric_filter.root_sign.metric_transformation[0].name
  namespace           = aws_cloudwatch_log_metric_filter.root_sign.metric_transformation[0].namespace
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions

  tags = var.tags
}
