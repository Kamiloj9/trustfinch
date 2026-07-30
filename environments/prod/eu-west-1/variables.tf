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

variable "gitlab_terraform_deployment" {
  type = object({
    oidc_provider_arn        = string
    oidc_provider_url        = string
    audience                 = string
    plan_subjects            = list(string)
    apply_subjects           = list(string)
    plan_additional_claims   = map(list(string))
    apply_additional_claims  = map(list(string))
    plan_policy_arns         = list(string)
    apply_policy_arns        = list(string)
    permissions_boundary_arn = string
  })
  description = "Optional GitLab CI deployment roles. Both roles use AWS STS web identity; apply is reserved for separate protected deployment tags."
  default     = null
  nullable    = true

  validation {
    condition = var.gitlab_terraform_deployment == null || (
      var.gitlab_terraform_deployment.audience == "sts.amazonaws.com" &&
      length(var.gitlab_terraform_deployment.plan_subjects) > 0 &&
      length(var.gitlab_terraform_deployment.apply_subjects) > 0 &&
      alltrue([for subject in var.gitlab_terraform_deployment.plan_subjects : can(regex("^project_(path|id):[^:*]+:ref_type:branch:ref:[^:*]+$", subject))]) &&
      alltrue([for subject in var.gitlab_terraform_deployment.apply_subjects : can(regex("^project_(path|id):[^:*]+:ref_type:tag:ref:[^:*]+$", subject))])
    )
    error_message = "GitLab Terraform deployment requires the STS audience, exact branch subjects for plans, and exact deployment-tag subjects for applies."
  }
}

variable "runtime_artifact_signing" {
  type = object({
    key_administrator_arns    = list(string)
    artifact_signer_role_arns = list(string)
    verification_enabled      = bool
  })
  description = "Optional isolated KMS key and verifier for signed runtime artifact manifests. Enable verification only after the release manifest has been signed and uploaded."
  default     = null
  nullable    = true

  validation {
    condition = var.runtime_artifact_signing == null || (
      length(var.runtime_artifact_signing.key_administrator_arns) > 0 &&
      length(var.runtime_artifact_signing.artifact_signer_role_arns) > 0
    )
    error_message = "Runtime artifact signing needs separate key administrators and at least one release signer role."
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

variable "enable_waf_rate_limit" {
  type        = bool
  description = "Attach the per-source-IP WAF rate limit to the public CA ALB."
  default     = true
}

variable "waf_rate_limit" {
  type        = number
  description = "Maximum requests per source IP over five minutes before WAF blocks that IP."
  default     = 500

  validation {
    condition     = var.waf_rate_limit >= 10
    error_message = "waf_rate_limit must be at least 10 requests per five-minute window."
  }
}

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

variable "intermediate_kms_sign_alarm_threshold" {
  type        = number
  description = "Reviewed maximum intermediate-KMS signing operations in five minutes before an abuse/cost alarm fires."
  default     = 500

  validation {
    condition     = var.intermediate_kms_sign_alarm_threshold >= 1
    error_message = "intermediate_kms_sign_alarm_threshold must be at least one request per five minutes."
  }
}

variable "postgres_instance_class" {
  type    = string
  default = "db.t4g.medium"
}
