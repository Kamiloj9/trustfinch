output "runtime_log_group_name" {
  value       = "/pki/${var.name}/runtime"
  description = "Name reserved for the step-ca and Caddy Docker logs."
}

output "cloudtrail_log_group_name" {
  value       = aws_cloudwatch_log_group.trail.name
  description = "CloudTrail log group name."
}

output "audit_bucket_name" {
  value       = aws_s3_bucket.audit.id
  description = "Versioned CloudTrail audit bucket."
}
