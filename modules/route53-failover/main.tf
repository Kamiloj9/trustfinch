resource "aws_route53_record" "primary" {
  zone_id        = var.hosted_zone_id
  name           = var.ca_fqdn
  type           = "A"
  set_identifier = "primary"

  failover_routing_policy {
    type = "PRIMARY"
  }

  alias {
    name                   = var.primary_load_balancer_dns_name
    zone_id                = var.primary_load_balancer_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "secondary" {
  zone_id        = var.hosted_zone_id
  name           = var.ca_fqdn
  type           = "A"
  set_identifier = "secondary"

  failover_routing_policy {
    type = "SECONDARY"
  }

  alias {
    name                   = var.secondary_load_balancer_dns_name
    zone_id                = var.secondary_load_balancer_zone_id
    evaluate_target_health = true
  }
}
