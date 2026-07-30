output "key_id" {
  value       = aws_kms_key.this.key_id
  description = "Use with ceremony/sign-runtime-artifacts.sh under a reviewed artifact-signing role."
}

output "key_arn" {
  value       = aws_kms_key.this.arn
  description = "Runtime-artifact signing KMS key ARN."
}

output "public_key_pem" {
  value       = data.aws_kms_public_key.this.public_key_pem
  description = "Public verification key embedded in runtime bootstrap; it cannot sign artifacts."
}
