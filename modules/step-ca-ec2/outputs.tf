output "runtime_role_arn" {
  value       = aws_iam_role.runtime.arn
  description = "Runtime role ARN used in the KMS key policy."
}

output "runtime_role_name" {
  value       = aws_iam_role.runtime.name
  description = "Runtime role name for attaching narrowly scoped policies."
}

output "artifact_bucket_name" {
  value       = aws_s3_bucket.artifacts.id
  description = "Bucket that holds only runtime config and reviewed public certificates."
}

output "public_ip" {
  value       = aws_eip.runtime.public_ip
  description = "Stable Lean/PoC endpoint IP."
}

output "state_volume_id" {
  value       = aws_instance.runtime.root_block_device[0].volume_id
  description = "ID of the encrypted EBS volume containing the Lean step-ca issuance state."
}
