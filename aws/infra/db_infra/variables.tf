variable "region" {
  type = string
}

variable "rds_instance_type" {
  type = string
}

variable "ec2_instance_type" {
  type = string
}

variable "halle_office" {
  type = string
}

variable "sf_office" {
  type = string
}

variable "db_port" {
  type = number
  default = 5432
}

variable "db_password" {
  type = string
}

variable "db_username" {
  type = string
}

variable "ssh_public_key" {
  type = string
}

variable "ssh_private_key" {
  type = string
}