variable "name" {
  type        = string
  description = "Short resource-name prefix."
}

variable "resource_arns" {
  type        = list(string)
  description = "Exact protected resource ARNs. Do not use wildcard or tag-based selections for PKI state."

  validation {
    condition     = length(var.resource_arns) > 0 && alltrue([for arn in var.resource_arns : startswith(arn, "arn:") && !strcontains(arn, "*")])
    error_message = "resource_arns must contain at least one exact, non-wildcard ARN."
  }
}

variable "retention_days" {
  type        = number
  description = "Number of days to retain each daily CA-state recovery point."
  default     = 35

  validation {
    condition     = var.retention_days >= 7 && var.retention_days <= 3650
    error_message = "retention_days must be between 7 and 3650 days."
  }
}

variable "schedule_expression" {
  type        = string
  description = "AWS EventBridge cron expression for daily state snapshots, evaluated in UTC."
  default     = "cron(0 3 * * ? *)"

  validation {
    condition     = can(regex("^cron\\(.+\\)$", var.schedule_expression))
    error_message = "schedule_expression must be an AWS cron expression."
  }
}

variable "alarm_actions" {
  type        = list(string)
  description = "SNS or incident-management action ARNs for failed or expired backup jobs."
  default     = []
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to backup resources and recovery points."
  default     = {}
}
