output "endpoint" {
  value = aws_db_instance.this.address
}

output "port" {
  value = aws_db_instance.this.port
}

output "master_secret_arn" {
  value = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "database_name" {
  value = var.database_name
}

output "username" {
  value = var.username
}

output "instance_identifier" {
  value       = aws_db_instance.this.identifier
  description = "CloudWatch RDS metric dimension value."
}
