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
  count = var.root_key_arn == null ? 0 : 1

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
  count = var.root_key_arn == null ? 0 : 1

  alarm_name          = "${var.name}-root-kms-sign"
  alarm_description   = "Every root CA signing operation requires incident review."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = aws_cloudwatch_log_metric_filter.root_sign[0].metric_transformation[0].name
  namespace           = aws_cloudwatch_log_metric_filter.root_sign[0].metric_transformation[0].namespace
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions

  tags = var.tags
}

resource "aws_cloudwatch_log_metric_filter" "intermediate_kms_sign_error" {
  count = var.intermediate_key_arn == null ? 0 : 1

  name           = "${var.name}-intermediate-kms-sign-error"
  log_group_name = aws_cloudwatch_log_group.trail.name
  pattern        = "{ ($.eventSource = \"kms.amazonaws.com\") && ($.eventName = \"Sign\") && ($.resources[0].ARN = \"${var.intermediate_key_arn}\") && ($.errorCode = \"*\") }"

  metric_transformation {
    name          = "IntermediateKmsSignErrors"
    namespace     = "PKI/${var.name}"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "intermediate_kms_sign_error" {
  count = var.intermediate_key_arn == null ? 0 : 1

  alarm_name          = "${var.name}-intermediate-kms-sign-error"
  alarm_description   = "A failed intermediate CA KMS signing request can interrupt certificate issuance."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = aws_cloudwatch_log_metric_filter.intermediate_kms_sign_error[0].metric_transformation[0].name
  namespace           = "PKI/${var.name}"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions

  tags = var.tags
}

resource "aws_cloudwatch_log_metric_filter" "intermediate_kms_sign" {
  count = var.intermediate_key_arn == null ? 0 : 1

  name           = "${var.name}-intermediate-kms-sign"
  log_group_name = aws_cloudwatch_log_group.trail.name
  pattern        = "{ ($.eventSource = \"kms.amazonaws.com\") && ($.eventName = \"Sign\") && ($.resources[0].ARN = \"${var.intermediate_key_arn}\") }"

  metric_transformation {
    name      = "IntermediateKmsSigns"
    namespace = "PKI/${var.name}"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "intermediate_kms_sign_volume" {
  count = var.intermediate_key_arn == null || var.intermediate_kms_sign_alarm_threshold == null ? 0 : 1

  alarm_name          = "${var.name}-intermediate-kms-sign-volume"
  alarm_description   = "Intermediate KMS signing volume exceeded the reviewed five-minute abuse and cost threshold."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = aws_cloudwatch_log_metric_filter.intermediate_kms_sign[0].metric_transformation[0].name
  namespace           = "PKI/${var.name}"
  period              = 300
  statistic           = "Sum"
  threshold           = var.intermediate_kms_sign_alarm_threshold
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions

  tags = var.tags
}

resource "aws_cloudwatch_log_metric_filter" "issued_certificates" {
  count = var.runtime_log_group_name == null ? 0 : 1

  name           = "${var.name}-issued-certificates"
  log_group_name = var.runtime_log_group_name
  pattern        = "{ ($.name = \"ca\") && ($.path = \"/sign\") && ($.status = 201) && ($.provisioner = \"*\") }"

  metric_transformation {
    name       = "IssuedCertificates"
    namespace  = "PKI/${var.name}"
    value      = "1"
    dimensions = { Provisioner = "$.provisioner" }
  }
}

resource "aws_cloudwatch_log_metric_filter" "ca_client_error" {
  count = var.runtime_log_group_name == null ? 0 : 1

  name           = "${var.name}-ca-4xx"
  log_group_name = var.runtime_log_group_name
  pattern        = "{ ($.name = \"ca\") && ($.status >= 400) && ($.status < 500) }"

  metric_transformation {
    name          = "CA4xxResponses"
    namespace     = "PKI/${var.name}"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_log_metric_filter" "ca_server_error" {
  count = var.runtime_log_group_name == null ? 0 : 1

  name           = "${var.name}-ca-5xx"
  log_group_name = var.runtime_log_group_name
  pattern        = "{ ($.name = \"ca\") && ($.status >= 500) }"

  metric_transformation {
    name          = "CA5xxResponses"
    namespace     = "PKI/${var.name}"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_log_metric_filter" "sign_latency" {
  count = var.runtime_log_group_name == null ? 0 : 1

  name           = "${var.name}-sign-latency"
  log_group_name = var.runtime_log_group_name
  pattern        = "{ ($.name = \"ca\") && ($.path = \"/sign\") && ($.status = 201) && ($.duration-ns = \"*\") }"

  metric_transformation {
    name      = "SignLatencyNanoseconds"
    namespace = "PKI/${var.name}"
    value     = "$.duration-ns"
  }
}

resource "aws_cloudwatch_metric_alarm" "ca_server_error" {
  count = var.runtime_log_group_name == null ? 0 : 1

  alarm_name          = "${var.name}-ca-5xx"
  alarm_description   = "A 5xx response from step-ca requires immediate investigation."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = aws_cloudwatch_log_metric_filter.ca_server_error[0].metric_transformation[0].name
  namespace           = "PKI/${var.name}"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "ca_client_error" {
  count = var.runtime_log_group_name == null ? 0 : 1

  alarm_name          = "${var.name}-ca-4xx-volume"
  alarm_description   = "Sustained CA 4xx responses can indicate an enrollment failure or abuse."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = aws_cloudwatch_log_metric_filter.ca_client_error[0].metric_transformation[0].name
  namespace           = "PKI/${var.name}"
  period              = 300
  statistic           = "Sum"
  threshold           = 20
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "sign_latency" {
  count = var.runtime_log_group_name == null ? 0 : 1

  alarm_name          = "${var.name}-sign-latency"
  alarm_description   = "Average certificate signing latency exceeded one second."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = aws_cloudwatch_log_metric_filter.sign_latency[0].metric_transformation[0].name
  namespace           = "PKI/${var.name}"
  period              = 300
  statistic           = "Average"
  threshold           = 1000000000
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_targets" {
  count = var.load_balancer_arn_suffix == null || var.target_group_arn_suffix == null ? 0 : 1

  alarm_name          = "${var.name}-ca-unhealthy-target"
  alarm_description   = "An ALB target running step-ca is unhealthy; issuance redundancy is reduced."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Maximum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions

  dimensions = {
    LoadBalancer = var.load_balancer_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  count = var.load_balancer_arn_suffix == null || var.target_group_arn_suffix == null ? 0 : 1

  alarm_name          = "${var.name}-ca-target-5xx"
  alarm_description   = "The ALB received a 5xx response from a step-ca target."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions

  dimensions = {
    LoadBalancer = var.load_balancer_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "database_cpu" {
  count = var.database_instance_identifier == null ? 0 : 1

  alarm_name          = "${var.name}-database-cpu"
  alarm_description   = "Sustained RDS CPU pressure can delay certificate issuance and failover recovery."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions

  dimensions = {
    DBInstanceIdentifier = var.database_instance_identifier
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "database_free_storage" {
  count = var.database_instance_identifier == null ? 0 : 1

  alarm_name          = "${var.name}-database-free-storage"
  alarm_description   = "RDS free storage is below 10 GiB; protect issuance and revocation state before it is exhausted."
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 10737418240
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions

  dimensions = {
    DBInstanceIdentifier = var.database_instance_identifier
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "host_disk_used" {
  count = var.host_disk_metric_pki_name == null ? 0 : 1

  alarm_name          = "${var.name}-host-disk-used"
  alarm_description   = "The PKI runtime root filesystem is at least 85% used; protect CA availability before it fills."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 3
  metric_name         = "disk_used_percent"
  namespace           = "PKI/Host"
  period              = 300
  statistic           = "Maximum"
  threshold           = 85
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions

  dimensions = {
    PKIName = var.host_disk_metric_pki_name
  }

  tags = var.tags
}
