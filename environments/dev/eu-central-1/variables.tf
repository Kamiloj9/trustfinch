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

variable "gitlab_oidc" {
  type = object({
    issuer                = string
    broker_image          = string
    broker_jwk_secret_arn = string
    broker_jwk_public = object({
      kty = string
      crv = string
      x   = string
      y   = string
      kid = string
    })
    identities = list(object({
      project_id   = string
      project_path = string
      audience     = string
      ref_type     = string
      ref          = string
      subject      = string
      uri_san      = string
    }))
  })
  description = "Optional protected-ref GitLab CI enrollment through the replay-protected broker. The private JWK stays in the referenced Secrets Manager secret."
  default     = null
  nullable    = true

  validation {
    condition = var.gitlab_oidc == null || (
      can(regex("^https://", var.gitlab_oidc.issuer)) &&
      can(regex("^.+@sha256:[0-9a-f]{64}$", var.gitlab_oidc.broker_image)) &&
      var.gitlab_oidc.broker_jwk_public.kty == "EC" &&
      var.gitlab_oidc.broker_jwk_public.crv == "P-256" &&
      length(var.gitlab_oidc.identities) > 0 &&
      alltrue([for identity in var.gitlab_oidc.identities : can(regex("^[0-9]+$", identity.project_id)) && can(regex("^https://", identity.audience)) && contains(["branch", "tag"], identity.ref_type) && can(regex("^spiffe://", identity.uri_san))])
    )
    error_message = "GitLab OIDC requires an HTTPS issuer, digest-pinned broker image, P-256 public JWK, and at least one valid protected-ref identity mapping."
  }
}

variable "iam_sigv4" {
  type = object({
    lambda_image                = string
    broker_jwk_secret_arn       = string
    ca_tls_root_certificate_pem = string
    broker_jwk_public = object({
      kty = string
      crv = string
      x   = string
      y   = string
      kid = string
    })
    identities = list(object({
      role_arn = string
      subject  = string
      uri_san  = string
    }))
  })
  description = "Optional API Gateway AWS_IAM enrollment. Lambda trusts only the SigV4-authenticated assumed role that maps to a fixed SPIFFE identity."
  default     = null
  nullable    = true

  validation {
    condition = var.iam_sigv4 == null || (
      can(regex("^.+@sha256:[0-9a-f]{64}$", var.iam_sigv4.lambda_image)) &&
      var.iam_sigv4.broker_jwk_public.kty == "EC" &&
      var.iam_sigv4.broker_jwk_public.crv == "P-256" &&
      length(var.iam_sigv4.identities) > 0 &&
      alltrue([for identity in var.iam_sigv4.identities : can(regex("^arn:(aws|aws-us-gov|aws-cn):iam::[0-9]{12}:role/.+$", identity.role_arn)) && can(regex("^spiffe://", identity.uri_san))])
    )
    error_message = "IAM SigV4 enrollment requires a digest-pinned arm64 Lambda image, P-256 public JWK, and explicit IAM role-to-SPIFFE mappings."
  }
}

variable "acme" {
  type = object({
    dns_allowlist = list(string)
  })
  description = "Optional ACME server-auth enrollment. Every approved DNS pattern must be a lowercase wildcard subdomain."
  default     = null
  nullable    = true

  validation {
    condition = var.acme == null || (
      length(var.acme.dns_allowlist) > 0 &&
      length(distinct(var.acme.dns_allowlist)) == length(var.acme.dns_allowlist) &&
      alltrue([for dns_name in var.acme.dns_allowlist : dns_name == lower(dns_name) && can(regex("^\\*\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", dns_name))])
    )
    error_message = "ACME requires at least one unique lowercase wildcard subdomain, for example *.apps.example.internal."
  }
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

variable "backup_retention_days" {
  type        = number
  description = "Retention for the daily AWS Backup recovery point of the encrypted Lean CA-state volume."
  default     = 35

  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 3650
    error_message = "backup_retention_days must be between 7 and 3650 days."
  }
}
