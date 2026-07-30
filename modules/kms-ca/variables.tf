variable "name" {
  type        = string
  description = "Resource-name prefix."
}

variable "runtime_role_arn" {
  type        = string
  description = "EC2 runtime role. It receives access only to the intermediate key."
}

variable "create_root_key" {
  type        = bool
  description = "Create the shared root key. Set false for an independent regional intermediate that chains to an existing root."
  default     = true
}

variable "key_administrator_arns" {
  type        = list(string)
  description = "Key administrators; keep distinct from ceremony and runtime roles."

  validation {
    condition     = length(var.key_administrator_arns) > 0
    error_message = "At least one key administrator role ARN is required."
  }
}

variable "root_ceremony_role_arns" {
  type        = list(string)
  description = "Roles permitted to sign with the root during an approved ceremony."

  validation {
    condition     = !var.create_root_key || length(var.root_ceremony_role_arns) > 0
    error_message = "At least one root ceremony role ARN is required when this module creates a root key."
  }
}

variable "intermediate_ceremony_role_arns" {
  type        = list(string)
  description = "Roles that may inspect the intermediate public key during ceremony."
  default     = []
}

variable "root_key_enabled" {
  type        = bool
  description = "Enable only for a reviewed root ceremony; default is disabled."
  default     = false
}

variable "deletion_window_in_days" {
  type        = number
  description = "KMS deletion waiting period."
  default     = 30

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "KMS deletion window must be between 7 and 30 days."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources."
  default     = {}
}
