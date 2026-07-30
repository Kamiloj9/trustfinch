variable "name" {
  type = string
}

variable "lambda_image_uri" {
  type        = string
  description = "Immutable ECR image digest for the arm64 IAM enrollment Lambda."

  validation {
    condition     = can(regex("^.+@sha256:[0-9a-f]{64}$", var.lambda_image_uri))
    error_message = "lambda_image_uri must use an immutable sha256 digest."
  }
}

variable "jwk_secret_arn" {
  type        = string
  description = "Secrets Manager ARN holding only the private P-256 JWK for the IAM broker provisioner."
}

variable "broker_config_json" {
  type        = string
  description = "Reviewed public IAM broker configuration. Private JWK material must never appear here."

  validation {
    condition     = !strcontains(var.broker_config_json, "\"d\":")
    error_message = "broker_config_json must not contain private key material."
  }
}

variable "log_retention_days" {
  type    = number
  default = 90
}

variable "reserved_concurrent_executions" {
  type        = number
  default     = 10
  description = "Hard upper bound for simultaneous IAM enrollments to contain KMS-signing cost and abuse."

  validation {
    condition     = var.reserved_concurrent_executions >= 1 && var.reserved_concurrent_executions <= 100
    error_message = "reserved_concurrent_executions must be between 1 and 100."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
