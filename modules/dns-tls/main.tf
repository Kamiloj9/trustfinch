resource "aws_route53_record" "ca" {
  count = var.hosted_zone_id == null ? 0 : 1

  zone_id = var.hosted_zone_id
  name    = var.ca_fqdn
  type    = "A"
  ttl     = 60
  records = [var.public_ip]
}
