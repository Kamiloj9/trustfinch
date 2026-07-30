variable "name" {
  type        = string
  description = "Resource-name prefix."
}

variable "key_administrator_arns" {
  type        = list(string)
  description = "Key administrators, distinct from release signers."

  validation {
    condition     = length(var.key_administrator_arns) > 0
    error_message = "At least one key administrator role ARN is required."
  }
}

variable "artifact_signer_role_arns" {
  type        = list(string)
  description = "Roles allowed to sign reviewed runtime-artifact manifests."

  validation {
    condition     = length(var.artifact_signer_role_arns) > 0
    error_message = "At least one artifact signer role ARN is required."
  }
}

variable "deletion_window_in_days" {
  type        = number
  description = "KMS deletion waiting period."
  default     = 30

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "deletion_window_in_days must be between 7 and 30."
  }
}

variable "tags" {
  type        = map(string)
  description = "Resource tags."
  default     = {}
}
