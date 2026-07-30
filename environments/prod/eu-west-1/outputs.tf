output "intermediate_key_id" {
  value = module.kms_ca.intermediate_key_id
}

output "artifact_bucket" {
  value = module.step_ca_ha.artifact_bucket_name
}

output "load_balancer_dns_name" {
  value = module.step_ca_ha.load_balancer_dns_name
}

output "load_balancer_zone_id" {
  value = module.step_ca_ha.load_balancer_zone_id
}

output "postgres_endpoint" {
  value = module.postgres.endpoint
}

output "iam_enrollment_endpoint" {
  value       = try(module.iam_enrollment_gateway[0].api_endpoint, null)
  description = "SigV4-only IAM enrollment endpoint when iam_sigv4 is enabled."
}

output "iam_enrollment_invoke_policy_json" {
  value       = try(module.iam_enrollment_gateway[0].invoke_policy_json, null)
  description = "Attach only to IAM roles explicitly approved in iam_sigv4.identities."
}

output "gitlab_terraform_plan_role_arn" {
  value       = try(module.gitlab_terraform_deployment[0].plan_role_arn, null)
  description = "Protected GitLab CI variable value for the Terraform plan job when GitLab deployment OIDC is enabled."
}

output "gitlab_terraform_apply_role_arn" {
  value       = try(module.gitlab_terraform_deployment[0].apply_role_arn, null)
  description = "Protected GitLab CI variable value for the Terraform apply job when GitLab deployment OIDC is enabled."
}

output "runtime_artifact_signing_key_id" {
  value       = try(module.runtime_artifact_signing[0].key_id, null)
  description = "Use only from the approved release signer role to sign the current runtime manifest."
}
