variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "name" {
  type    = string
  default = "pki-prod-euc1"
}

variable "ca_fqdn" {
  type = string
}

variable "internal_dns_suffix" {
  type = string
}

variable "trust_domain" {
  type = string
}

variable "runtime_release_id" {
  type        = string
  description = "Increment for each reviewed config, public-certificate, or runtime image release."
}

variable "vpc_cidr" {
  type    = string
  default = "10.80.0.0/20"
}

variable "availability_zones" {
  type = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "Production HA requires two or more availability zones."
  }
}

variable "allowed_https_cidrs" {
  type = list(string)
}

variable "acm_certificate_arn" {
  type        = string
  description = "Regional ACM certificate for ca_fqdn, used by the ALB listener."
}

variable "hosted_zone_id" {
  type     = string
  default  = null
  nullable = true
}

variable "key_administrator_arns" {
  type = list(string)
}

variable "root_ceremony_role_arns" {
  type = list(string)
}

variable "certificate_publisher_role_arns" {
  type    = list(string)
  default = []
}

variable "root_key_enabled" {
  type    = bool
  default = false
}

variable "alarm_actions" {
  type    = list(string)
  default = []
}

variable "postgres_instance_class" {
  type    = string
  default = "db.t4g.medium"
}
