variable "name" {
  type        = string
  description = "Resource-name prefix."
}

variable "vpc_id" {
  type        = string
  description = "VPC for the runtime security group."
}

variable "subnet_id" {
  type        = string
  description = "Public subnet for the Lean/PoC runtime."
}

variable "cloudwatch_log_group_name" {
  type        = string
  description = "CloudWatch log group used by the Docker awslogs driver."
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

variable "ami_id" {
  type        = string
  description = "Optional ARM64 Amazon Linux 2023 AMI ID. Null uses AWS's public SSM parameter."
  default     = null
  nullable    = true
}

variable "instance_type" {
  type        = string
  description = "Graviton instance type."
  default     = "t4g.small"
}

variable "allowed_https_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to reach the CA endpoint. Use VPN CIDRs for a private deployment."
}

variable "root_volume_size" {
  type        = number
  description = "Encrypted gp3 root volume size in GiB."
  default     = 20
}

variable "certificate_publisher_role_arns" {
  type        = list(string)
  description = "Ceremony roles permitted to upload reviewed public certificates to the artifact bucket."
  default     = []
}

variable "artifact_verification_enabled" {
  type        = bool
  description = "Require a KMS-signed manifest before the runtime accepts S3 artifacts."
  default     = false
}

variable "artifact_signing_public_key_pem" {
  type        = string
  description = "Public PEM key for detached runtime-artifact manifest verification."
  default     = null
  nullable    = true

  validation {
    condition     = var.artifact_signing_public_key_pem == null || can(regex("BEGIN PUBLIC KEY", var.artifact_signing_public_key_pem))
    error_message = "artifact_signing_public_key_pem must be a PEM public key when set."
  }
}

variable "artifact_signer_role_arns" {
  type        = list(string)
  description = "Release signer roles permitted to read artifacts and publish only their signed manifest files."
  default     = []
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources."
  default     = {}
}
