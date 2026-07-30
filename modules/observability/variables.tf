variable "name" {
  type        = string
  description = "Resource-name prefix."
}

variable "root_key_arn" {
  type        = string
  description = "Optional local root KMS key ARN monitored for every Sign event. Independent intermediate-only regions set this to null."
  default     = null
  nullable    = true
}

variable "intermediate_key_arn" {
  type        = string
  description = "Optional intermediate KMS key ARN monitored for failed signing requests."
  default     = null
  nullable    = true
}

variable "runtime_log_group_name" {
  type        = string
  description = "Optional CloudWatch log group receiving sanitized step-ca JSON logs."
  default     = null
  nullable    = true
}

variable "alarm_actions" {
  type        = list(string)
  description = "Optional SNS or incident-management alarm action ARNs."
  default     = []
}

variable "log_retention_days" {
  type        = number
  description = "CloudWatch log retention."
  default     = 365
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources."
  default     = {}
}
