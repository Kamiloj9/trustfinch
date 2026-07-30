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
