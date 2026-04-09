variable "compartment_ocid" {
  type = string
}

variable "vcn_id" {
  type = string
}

variable "subnet_oke_api_id" {
  type        = string
  description = "Public subnet for OKE API endpoint"
}

variable "subnet_pub_id" {
  type        = string
  description = "Public subnet for Service Load Balancers"
}

variable "subnet_workers_id" {
  type        = string
  description = "Private subnet for worker nodes"
}

variable "availability_domain" {
  type = string
}

variable "kubernetes_version" {
  type = string
}

variable "ssh_authorized_keys" {
  type = string
}

variable "user_data_file" {
  type = string
}
