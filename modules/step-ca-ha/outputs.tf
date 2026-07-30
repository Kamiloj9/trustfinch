output "runtime_role_arn" {
  value = aws_iam_role.runtime.arn
}

output "runtime_role_name" {
  value = aws_iam_role.runtime.name
}

output "node_security_group_id" {
  value = aws_security_group.nodes.id
}

output "artifact_bucket_name" {
  value = aws_s3_bucket.artifacts.id
}

output "load_balancer_dns_name" {
  value = aws_lb.this.dns_name
}

output "load_balancer_zone_id" {
  value = aws_lb.this.zone_id
}
