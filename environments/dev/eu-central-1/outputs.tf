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
