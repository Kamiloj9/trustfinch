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
