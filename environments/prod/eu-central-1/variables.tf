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
  description = "Optional API Gateway AWS_IAM enrollment. Only SigV4-authenticated assumed roles explicitly mapped to a fixed SPIFFE identity can obtain certificates."
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
