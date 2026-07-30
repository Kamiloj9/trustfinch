variable "name" {
  type = string
}

variable "runtime_role_name" {
  type        = string
  description = "The step-ca runtime role whose broker sidecar consumes GitLab token IDs."
}

variable "tags" {
  type    = map(string)
  default = {}
}
