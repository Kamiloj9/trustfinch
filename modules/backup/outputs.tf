output "vault_name" {
  value       = aws_backup_vault.this.name
  description = "AWS Backup vault holding Lean CA-state recovery points."
}

output "vault_arn" {
  value       = aws_backup_vault.this.arn
  description = "ARN of the CA-state recovery vault."
}

output "plan_id" {
  value       = aws_backup_plan.this.id
  description = "AWS Backup plan ID to use when reviewing recovery points and jobs."
}

output "job_error_alarm_arns" {
  value       = { for name, alarm in aws_cloudwatch_metric_alarm.job_error : name => alarm.arn }
  description = "CloudWatch alarms for failed or expired CA-state backup jobs."
}
