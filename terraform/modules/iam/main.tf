terraform {
  required_providers {
    oci = {
      source = "oracle/oci"
    }
  }
}

# ──────────────────────────────────────────
# NSG — 허용 IP에서 모든 포트 접근 가능
# ──────────────────────────────────────────
resource "oci_core_network_security_group" "public_access" {
  compartment_id = var.compartment_ocid
  vcn_id         = var.vcn_id
  display_name   = "nsg-public-access"
}

resource "oci_core_network_security_group_security_rule" "allow_all" {
  network_security_group_id = oci_core_network_security_group.public_access.id
  direction                 = "INGRESS"
  protocol                  = "all"
  source                    = var.allowed_cidr
  source_type               = "CIDR_BLOCK"
}
