output "root_key_id" {
  value       = module.kms_ca.root_key_id
  description = "Use only in the approved root ceremony."
}

output "intermediate_key_id" {
  value       = module.kms_ca.intermediate_key_id
  description = "Use in the approved ceremony and generated step-ca config."
}

output "artifact_bucket" {
  value       = module.step_ca_ec2.artifact_bucket_name
  description = "Destination for reviewed public CA certificates."
}

output "ca_public_ip" {
  value       = module.step_ca_ec2.public_ip
  description = "Lean/PoC endpoint address."
}

output "ca_dns_name" {
  value       = module.dns.record_fqdn
  description = "Route 53 record if this module owns DNS."
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

output "ca_state_backup_vault" {
  value       = module.backup.vault_name
  description = "AWS Backup vault with daily recovery points for the Lean CA issuance-state volume."
}
