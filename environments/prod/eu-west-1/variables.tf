variable "aws_region" {
  type    = string
  default = "eu-west-1"
}

variable "name" {
  type    = string
  default = "pki-prod-euw1"
}

variable "ca_fqdn" { type = string }
variable "internal_dns_suffix" { type = string }
variable "trust_domain" { type = string }
variable "runtime_release_id" { type = string }

variable "google_oidc" {
  type = object({
    client_id         = string
    workspace_domain  = string
    client_secret_arn = string
  })
  default  = null
  nullable = true
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

variable "aws_iid_accounts" {
  type    = list(string)
  default = []
}

variable "aws_iid_dns_allowlist" {
  type    = list(string)
  default = []
}

variable "aws_iid_instance_age" {
  type    = string
  default = "5m"
}

variable "vpc_cidr" {
  type    = string
  default = "10.96.0.0/20"
}

variable "availability_zones" { type = list(string) }
variable "allowed_https_cidrs" { type = list(string) }
variable "acm_certificate_arn" { type = string }

variable "hosted_zone_id" {
  type     = string
  default  = null
  nullable = true
}

variable "key_administrator_arns" { type = list(string) }
variable "intermediate_ceremony_role_arns" { type = list(string) }
variable "certificate_publisher_role_arns" {
  type    = list(string)
  default = []
}

variable "alarm_actions" {
  type    = list(string)
  default = []
}

variable "postgres_instance_class" {
  type    = string
  default = "db.t4g.medium"
}
