variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "client_security_group_id" {
  type = string
}

variable "instance_class" {
  type    = string
  default = "db.t4g.medium"
}

variable "database_name" {
  type    = string
  default = "stepca"
}

variable "username" {
  type    = string
  default = "stepca"
}

variable "backup_retention_days" {
  type    = number
  default = 35
}

variable "engine_version" {
  type     = string
  default  = null
  nullable = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
