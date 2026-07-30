variable "name" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "availability_zones" {
  type = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "The HA profile requires at least two availability zones."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
