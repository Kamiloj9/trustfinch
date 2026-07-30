data "aws_iam_policy_document" "assume_backup" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# This role is assumed exclusively by AWS Backup. The CA runtime has no
# permission to create, delete, or restore its own recovery points.
resource "aws_iam_role" "service" {
  name               = "${var.name}-pki-backup-service"
  assume_role_policy = data.aws_iam_policy_document.assume_backup.json
  tags               = merge(var.tags, { Name = "${var.name}-pki-backup-service" })
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.service.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "restore" {
  role       = aws_iam_role.service.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

resource "aws_backup_vault" "this" {
  name = "${var.name}-pki-state"
  tags = merge(var.tags, {
    Name      = "${var.name}-pki-state"
    DataClass = "pki-issuance-state"
  })
}

resource "aws_backup_plan" "this" {
  name = "${var.name}-pki-state"

  rule {
    rule_name         = "daily-state-snapshot"
    target_vault_name = aws_backup_vault.this.name
    schedule          = var.schedule_expression
    start_window      = 60
    completion_window = 180

    lifecycle {
      delete_after = var.retention_days
    }

    recovery_point_tags = merge(var.tags, {
      BackupPlan = "${var.name}-pki-state"
      DataClass  = "pki-issuance-state"
    })
  }

  tags = merge(var.tags, { Name = "${var.name}-pki-state" })
}

# Explicit ARNs avoid a broad tag selection that could silently include an
# unrelated database or volume and increase both scope and cost.
resource "aws_backup_selection" "this" {
  iam_role_arn = aws_iam_role.service.arn
  name         = "pki-state-only"
  plan_id      = aws_backup_plan.this.id
  resources    = var.resource_arns

  depends_on = [
    aws_iam_role_policy_attachment.backup,
    aws_iam_role_policy_attachment.restore,
  ]
}

# A missing metric before the first scheduled run is normal. A job that fails
# or misses its start window is not: it must reach the same incident actions
# used by the root-key monitoring path.
resource "aws_cloudwatch_metric_alarm" "job_error" {
  for_each = {
    failed  = "NumberOfBackupJobsFailed"
    expired = "NumberOfBackupJobsExpired"
  }

  alarm_name          = "${var.name}-pki-backup-${each.key}"
  alarm_description   = "A CA-state AWS Backup job ${each.key}; investigate before the next recovery-point window."
  namespace           = "AWS/Backup"
  metric_name         = each.value
  statistic           = "Sum"
  period              = 86400
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions

  dimensions = {
    BackupVaultName = aws_backup_vault.this.name
  }

  tags = var.tags
}
