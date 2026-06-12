terraform {
  required_providers {
    oci = {
      source = "oracle/oci"
    }
  }
}

# ──────────────────────────────────────────
# NSG — 외부 admin/public 접근 (포트 명시)
# ──────────────────────────────────────────
resource "oci_core_network_security_group" "public_access" {
  compartment_id = var.compartment_ocid
  vcn_id         = var.vcn_id
  display_name   = "nsg-public-access"
}

# allowed IP → OKE API
resource "oci_core_network_security_group_security_rule" "kubectl_api" {
  network_security_group_id = oci_core_network_security_group.public_access.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = var.allowed_cidr
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 6443
      max = 6443
    }
  }
}

# allowed IP → LB HTTPS
resource "oci_core_network_security_group_security_rule" "https" {
  network_security_group_id = oci_core_network_security_group.public_access.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = var.allowed_cidr
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 443
      max = 443
    }
  }
}

# allowed IP → LB HTTP (redirect)
resource "oci_core_network_security_group_security_rule" "http" {
  network_security_group_id = oci_core_network_security_group.public_access.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = var.allowed_cidr
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 80
      max = 80
    }
  }
}

# ──────────────────────────────────────────
# Dynamic Group + Policy — instance principal
# ──────────────────────────────────────────

# 워커 인스턴스 매칭 (compartment 단위)
resource "oci_identity_dynamic_group" "workers" {
  compartment_id = var.tenancy_ocid
  name           = "dg-oke-workers"
  description    = "OKE worker instances (instance principal)"
  matching_rule  = "ALL {instance.compartment.id = '${var.compartment_ocid}'}"
}

# unseal 키 1개로 한정 (target.key.id)
resource "oci_identity_policy" "openbao_unseal" {
  compartment_id = var.compartment_ocid
  name           = "openbao-unseal"
  description    = "allow worker instances to use the OpenBao unseal key only"

  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.workers.name} to use keys in compartment id ${var.compartment_ocid} where target.key.id = '${var.unseal_key_id}'",
  ]
}
