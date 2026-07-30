output "root_key_id" {
  value       = try(aws_kms_key.root[0].key_id, null)
  description = "Root KMS key ID for the approved ceremony only."
}

output "root_key_arn" {
  value       = try(aws_kms_key.root[0].arn, null)
  description = "Root KMS key ARN for CloudTrail monitoring."
}

output "intermediate_key_id" {
  value       = aws_kms_key.intermediate.key_id
  description = "Intermediate KMS key ID used in step-ca configuration."
}

output "intermediate_key_arn" {
  value       = aws_kms_key.intermediate.arn
  description = "Intermediate KMS key ARN."
}
