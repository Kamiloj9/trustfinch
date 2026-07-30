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

variable "intermediate_kms_sign_alarm_threshold" {
  type        = number
  description = "Optional maximum intermediate KMS signing requests in five minutes before an abuse/cost alarm fires."
  default     = null
  nullable    = true

  validation {
    condition     = var.intermediate_kms_sign_alarm_threshold == null || var.intermediate_kms_sign_alarm_threshold >= 1
    error_message = "intermediate_kms_sign_alarm_threshold must be at least one request per five minutes when configured."
  }
}

variable "runtime_log_group_name" {
  type        = string
  description = "Optional CloudWatch log group receiving sanitized step-ca JSON logs."
  default     = null
  nullable    = true
}

variable "load_balancer_arn_suffix" {
  type        = string
  description = "Optional Application Load Balancer ARN suffix monitored for target health and 5xx responses."
  default     = null
  nullable    = true
}

variable "target_group_arn_suffix" {
  type        = string
  description = "Optional step-ca target-group ARN suffix paired with the Application Load Balancer metrics."
  default     = null
  nullable    = true
}

variable "database_instance_identifier" {
  type        = string
  description = "Optional RDS instance identifier monitored for capacity pressure."
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
