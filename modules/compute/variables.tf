variable "compartment_ocid" {
  type = string
}

variable "availability_domain" {
  type = string
}

variable "subnet_masters_id" {
  type = string
}

variable "ssh_authorized_keys" {
  type = string
}

variable "subnet_workers_id" {
  type = string
}

# variable "vault_id" {
#   type = string
# }

# variable "key_id" {
#   type = string
# }

variable "worker_subnet_cidr" {
  type = string
}

variable "lb_id" {
  type = string
}

variable "lb_backend_set_name" {
  type = string
}

variable "image_id" {
  type = string
}
