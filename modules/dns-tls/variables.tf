variable "hosted_zone_id" {
  type        = string
  description = "Optional Route 53 hosted zone ID. Null skips DNS record creation."
  default     = null
  nullable    = true
}

variable "ca_fqdn" {
  type        = string
  description = "CA endpoint fully-qualified domain name."
}

variable "public_ip" {
  type        = string
  description = "Lean/PoC Elastic IP target."
}
