output "vpc_id" {
  value       = aws_vpc.this.id
  description = "VPC ID."
}

output "public_subnet_ids" {
  value       = [for az in var.availability_zones : aws_subnet.public[az].id]
  description = "Public subnet IDs in the input AZ order."
}
