variable "compartment_ocid" {
  type = string
}

variable "vcn_id" {
  type = string
}

variable "allowed_cidr" {
  type        = string
  description = "공인 서비스 접근 허용 IP (e.g. 1.2.3.4/32)"
}
