variable "name" {
  type        = string
  description = "Short resource prefix for the two GitLab Terraform roles."
}

variable "oidc_provider_arn" {
  type        = string
  description = "Existing AWS IAM OIDC provider ARN for the GitLab ID-token issuer."

  validation {
    condition     = can(regex("^arn:(aws|aws-us-gov|aws-cn):iam::[0-9]{12}:oidc-provider/.+$", var.oidc_provider_arn))
    error_message = "oidc_provider_arn must be an IAM OIDC provider ARN."
  }
}

variable "oidc_provider_url" {
  type        = string
  description = "HTTPS issuer URL registered on the AWS IAM OIDC provider, without a trailing slash."

  validation {
    condition     = can(regex("^https://[^/]+(/[^/]+)*$", var.oidc_provider_url))
    error_message = "oidc_provider_url must be an HTTPS OIDC issuer URL without a trailing slash."
  }
}

variable "audience" {
  type        = string
  description = "GitLab ID-token audience accepted by AWS STS."

  validation {
    condition     = var.audience == "sts.amazonaws.com"
    error_message = "Terraform deployment roles must use the AWS STS audience sts.amazonaws.com."
  }
}

variable "plan_subjects" {
  type        = list(string)
  description = "Exact protected GitLab branch-subject values allowed to plan."

  validation {
    condition = length(var.plan_subjects) > 0 && length(distinct(var.plan_subjects)) == length(var.plan_subjects) && alltrue([
      for subject in var.plan_subjects : can(regex("^project_(path|id):[^:*]+:ref_type:branch:ref:[^:*]+$", subject))
    ])
    error_message = "plan_subjects must be unique exact GitLab branch subjects without wildcards."
  }
}

variable "apply_subjects" {
  type        = list(string)
  description = "Exact protected GitLab deployment-tag subject values allowed to apply."

  validation {
    condition = length(var.apply_subjects) > 0 && length(distinct(var.apply_subjects)) == length(var.apply_subjects) && alltrue([
      for subject in var.apply_subjects : can(regex("^project_(path|id):[^:*]+:ref_type:tag:ref:[^:*]+$", subject))
    ])
    error_message = "apply_subjects must be unique exact GitLab deployment-tag subjects without wildcards."
  }
}

variable "plan_additional_claims" {
  type        = map(list(string))
  description = "Optional immutable GitLab OIDC claims (for example project_id and ref_protected) required for plan sessions."
  default     = {}

  validation {
    condition = alltrue([
      for claim, values in var.plan_additional_claims : !contains(["aud", "sub"], claim) && can(regex("^[a-z_]+$", claim)) && length(values) > 0 && length(distinct(values)) == length(values)
    ])
    error_message = "Additional claim names must be non-empty lowercase GitLab claim names other than aud or sub, with unique values."
  }
}

variable "apply_additional_claims" {
  type        = map(list(string))
  description = "Optional immutable GitLab OIDC claims (for example project_id and ref_protected) required for apply sessions."
  default     = {}

  validation {
    condition = alltrue([
      for claim, values in var.apply_additional_claims : !contains(["aud", "sub"], claim) && can(regex("^[a-z_]+$", claim)) && length(values) > 0 && length(distinct(values)) == length(values)
    ])
    error_message = "Additional claim names must be non-empty lowercase GitLab claim names other than aud or sub, with unique values."
  }
}

variable "plan_policy_arns" {
  type        = list(string)
  description = "Reviewed customer-managed read-only policy ARNs for the plan role."

  validation {
    condition = length(var.plan_policy_arns) > 0 && length(distinct(var.plan_policy_arns)) == length(var.plan_policy_arns) && alltrue([
      for policy_arn in var.plan_policy_arns : can(regex("^arn:(aws|aws-us-gov|aws-cn):iam::[0-9]{12}:policy/.+$", policy_arn)) && !strcontains(policy_arn, "AdministratorAccess")
    ])
    error_message = "plan_policy_arns must contain unique customer-managed policies and must not include AdministratorAccess."
  }
}

variable "apply_policy_arns" {
  type        = list(string)
  description = "Reviewed environment-scoped customer-managed policy ARNs for the apply role."

  validation {
    condition = length(var.apply_policy_arns) > 0 && length(distinct(var.apply_policy_arns)) == length(var.apply_policy_arns) && alltrue([
      for policy_arn in var.apply_policy_arns : can(regex("^arn:(aws|aws-us-gov|aws-cn):iam::[0-9]{12}:policy/.+$", policy_arn)) && !strcontains(policy_arn, "AdministratorAccess")
    ])
    error_message = "apply_policy_arns must contain unique customer-managed policies and must not include AdministratorAccess."
  }
}

variable "permissions_boundary_arn" {
  type        = string
  description = "Required reviewed permission boundary ARN applied to both GitLab deployment roles."

  validation {
    condition     = can(regex("^arn:(aws|aws-us-gov|aws-cn):iam::[0-9]{12}:policy/.+$", var.permissions_boundary_arn))
    error_message = "permissions_boundary_arn must be a customer-managed IAM policy ARN."
  }
}

variable "tags" {
  type        = map(string)
  description = "Resource tags."
  default     = {}
}
