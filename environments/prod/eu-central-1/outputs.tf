output "root_key_id" {
  value = module.kms_ca.root_key_id
}

output "intermediate_key_id" {
  value = module.kms_ca.intermediate_key_id
}

output "artifact_bucket" {
  value = module.step_ca_ha.artifact_bucket_name
}

output "load_balancer_dns_name" {
  value = module.step_ca_ha.load_balancer_dns_name
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
