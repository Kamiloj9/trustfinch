variable "name" {
  type        = string
  description = "Resource-name prefix."
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR for the Lean/PoC VPC."
}

variable "availability_zones" {
  type        = list(string)
  description = "Availability zones used for public subnets. Lean uses one; HA uses a separate module/profile."

  validation {
    condition     = length(var.availability_zones) >= 1
    error_message = "At least one availability zone is required."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources."
  default     = {}
}
