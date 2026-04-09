variable "tenancy_ocid" {
  type = string
}

variable "user_ocid" {
  type = string
}

variable "fingerprint" {
  type = string
}

variable "private_key_path" {
  type = string
}

variable "region" {
  type = string
}

variable "compartment_ocid" {
  type = string
}

variable "ssh_authorized_keys" {
  type = string
}

variable "db_admin_password" {
  type      = string
  sensitive = true
}

variable "kubernetes_version" {
  type    = string
  default = "v1.34.2"
}
