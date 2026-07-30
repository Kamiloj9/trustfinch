output "plan_role_arn" {
  value       = aws_iam_role.plan.arn
  description = "Set this as the protected GitLab CI variable for Terraform plan jobs."
}

output "apply_role_arn" {
  value       = aws_iam_role.apply.arn
  description = "Set this as the protected GitLab CI variable for Terraform apply jobs."
}
