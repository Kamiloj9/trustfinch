output "record_fqdn" {
  value       = try(aws_route53_record.ca[0].fqdn, null)
  description = "Created Route 53 record, or null if DNS is managed externally."
}
