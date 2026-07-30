variable "aws_region" {
  type        = string
  description = "AWS region for the Lean/PoC deployment."
  default     = "eu-central-1"
}

variable "name" {
  type        = string
  description = "Short lowercase resource prefix."
  default     = "pki-dev"
}

variable "ca_fqdn" {
  type        = string
  description = "Public or private CA endpoint. Replace the example before apply."
  default     = "ca.dev.example.internal"
}

variable "internal_dns_suffix" {
  type        = string
  description = "DNS suffix certificates may contain. Replace the example before apply."
  default     = "dev.example.internal"
}

variable "trust_domain" {
  type        = string
  description = "SPIFFE trust domain allowed by the authority policy."
  default     = "dev.example.internal"
}

variable "google_oidc" {
  type = object({
    client_id         = string
    workspace_domain  = string
    client_secret_arn = string
  })
  description = "Optional Google Workspace native OIDC client. Its client secret stays in the referenced Secrets Manager JSON secret."
  default     = null
  nullable    = true
}

variable "aws_iid_accounts" {
  type        = list(string)
  description = "AWS account IDs allowed to use the conservative IID provisioner. An empty list disables it."
  default     = []

  validation {
    condition     = alltrue([for account in var.aws_iid_accounts : can(regex("^[0-9]{12}$", account))])
    error_message = "Every AWS IID account must be a 12-digit account ID."
  }
}

variable "aws_iid_dns_allowlist" {
  type        = list(string)
  description = "AWS internal DNS patterns allowed for IID-issued certificates, for example *.eu-central-1.compute.internal."
  default     = []
}

variable "aws_iid_instance_age" {
  type        = string
  description = "Maximum age of an EC2 instance's IID at its initial enrollment."
  default     = "5m"
}

variable "vpc_cidr" {
  type        = string
  description = "Lean/PoC VPC CIDR."
  default     = "10.60.0.0/20"
}

variable "availability_zones" {
  type        = list(string)
  description = "Use one AZ only for this PoC profile."
  default     = ["eu-central-1a"]
}

variable "allowed_https_cidrs" {
  type        = list(string)
  description = "Networks allowed to reach Caddy on the CA host."
  default     = ["0.0.0.0/0"]
}

variable "hosted_zone_id" {
  type        = string
  description = "Optional Route 53 zone ID; null leaves DNS external."
  default     = null
  nullable    = true
}

variable "key_administrator_arns" {
  type        = list(string)
  description = "KMS administration roles, distinct from ceremony/runtime roles."
}

variable "root_ceremony_role_arns" {
  type        = list(string)
  description = "Roles allowed to sign the root certificate during a ceremony."
}

variable "certificate_publisher_role_arns" {
  type        = list(string)
  description = "Roles allowed to upload reviewed public CA certificates."
  default     = []
}

variable "root_key_enabled" {
  type        = bool
  description = "Set true only for a reviewed root ceremony; it must return to false immediately afterward."
  default     = false
}

variable "alarm_actions" {
  type        = list(string)
  description = "Optional alarm action ARNs. Empty is valid only for initial PoC validation."
  default     = []
}
