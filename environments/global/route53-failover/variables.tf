variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "hosted_zone_id" { type = string }
variable "ca_fqdn" { type = string }
variable "primary_load_balancer_dns_name" { type = string }
variable "primary_load_balancer_zone_id" { type = string }
variable "secondary_load_balancer_dns_name" { type = string }
variable "secondary_load_balancer_zone_id" { type = string }
