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
  type    = string
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

variable "bastion_allowed_cidrs" {
  type = list(string)
  # Restrict to your own IP in tfvars (e.g. ["1.2.3.4/32"])
  validation {
    condition     = !contains(var.bastion_allowed_cidrs, "0.0.0.0/0")
    error_message = "0.0.0.0/0 is not allowed in bastion_allowed_cidrs. Restrict to your IP/32."
  }
}

variable "image_id" {
  type    = string
  default = "ocid1.image.oc1..aaaaaaaas7a4zwwsdtry2nsf6rqrvhgasczcyb2wxsx6x3pewxorcwr3d4pq"
}
