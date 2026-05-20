variable "compartment_ocid" {
  type = string
}

variable "availability_domain" {
  type = string
}

variable "volume_a_size_in_gbs" {
  type        = number
  default     = 53
  description = "Volume A: Vault + Prometheus + Jenkins"
}

variable "volume_b_size_in_gbs" {
  type        = number
  default     = 53
  description = "Volume B: Kafka + Redis + Tempo"
}
