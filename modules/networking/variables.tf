variable "compartment_ocid" {
  type = string
}

variable "bastion_allowed_cidrs" {
  type = list(string)
  # Must be restricted to your own IP in tfvars (e.g. ["1.2.3.4/32"])
}
