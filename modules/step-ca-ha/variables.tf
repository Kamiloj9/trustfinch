variable "name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "cloudwatch_log_group_arn" {
  type = string
}

variable "cloudwatch_log_group_name" {
  type = string
}

variable "database_secret_arn" {
  type = string
}

variable "google_oidc_client_secret_arn" {
  type        = string
  description = "Optional Secrets Manager ARN containing {\"client_secret\": \"...\"} for the Google Workspace OIDC native client."
  default     = null
  nullable    = true
}

variable "gitlab_broker_jwk_secret_arn" {
  type        = string
  description = "Optional Secrets Manager ARN containing the private P-256 JWK used only by the GitLab enrollment broker."
  default     = null
  nullable    = true
}

variable "gitlab_broker_enabled" {
  type        = bool
  description = "Expose the GitLab enrollment broker through a dedicated ALB target group."
  default     = false
}

variable "runtime_release_id" {
  type        = string
  description = "Reviewed runtime-artifact release identifier. Changing it performs a rolling ASG refresh."
}

variable "allowed_https_cidrs" {
  type = list(string)
}

variable "acm_certificate_arn" {
  type = string
}

variable "enable_waf_rate_limit" {
  type        = bool
  description = "Attach a regional WAF web ACL that blocks sustained request floods per source IP."
  default     = true
}

variable "waf_rate_limit" {
  type        = number
  description = "Maximum requests from one source IP during the WAF five-minute evaluation window."
  default     = 500

  validation {
    condition     = var.waf_rate_limit >= 10
    error_message = "waf_rate_limit must be at least 10 requests per five-minute window."
  }
}

variable "ami_id" {
  type     = string
  default  = null
  nullable = true
}

variable "instance_type" {
  type    = string
  default = "t4g.small"
}

variable "certificate_publisher_role_arns" {
  type    = list(string)
  default = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
