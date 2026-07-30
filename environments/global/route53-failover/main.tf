provider "aws" {
  region = var.aws_region
}

module "ca_failover" {
  source = "../../../modules/route53-failover"

  hosted_zone_id                   = var.hosted_zone_id
  ca_fqdn                          = var.ca_fqdn
  primary_load_balancer_dns_name   = var.primary_load_balancer_dns_name
  primary_load_balancer_zone_id    = var.primary_load_balancer_zone_id
  secondary_load_balancer_dns_name = var.secondary_load_balancer_dns_name
  secondary_load_balancer_zone_id  = var.secondary_load_balancer_zone_id
}
