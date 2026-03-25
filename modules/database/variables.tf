variable "compartment_ocid" {
  type = string
}

variable "subnet_db_id" {
  type = string
}

variable "availability_domain" {
  type = string
}

variable "admin_username" {
  type    = string
  default = "admin"
}

variable "admin_password" {
  type      = string
  sensitive = true
}
