terraform {
  required_providers {
    oci = {
      source = "oracle/oci"
    }
  }
}

# ──────────────────────────────────────────
# VCN
# ──────────────────────────────────────────
resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_ocid
  cidr_block     = "10.0.0.0/16"
  display_name   = "vcn-main"
  dns_label      = "vcnmain"
}

resource "oci_core_internet_gateway" "igw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "igw-main"
  enabled        = true
}

resource "oci_core_nat_gateway" "nat" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "nat-main"
}

data "oci_core_services" "all" {}

locals {
  # "All <Region> Services In Oracle Services Network" 을 명시적으로 선택
  # services[0] 인덱스는 리전마다 순서가 달라 Object Storage만 잡힐 수 있음
  all_services = [
    for s in data.oci_core_services.all.services :
    s if startswith(s.name, "All ")
  ][0]
}

resource "oci_core_service_gateway" "sgw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "sgw-main"

  services {
    service_id = local.all_services.id
  }
}

# ──────────────────────────────────────────
# Route Tables
# ──────────────────────────────────────────
resource "oci_core_route_table" "pub" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "rt-public"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.igw.id
  }
}

resource "oci_core_route_table" "workers" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "rt-workers"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.nat.id
  }

  route_rules {
    destination       = local.all_services.cidr_block
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.sgw.id
  }
}

resource "oci_core_route_table" "db" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "rt-db"

  # OCI 내부 서비스 접근 (패치, 백업 등) — 인터넷 노출 없음
  route_rules {
    destination       = local.all_services.cidr_block
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.sgw.id
  }
}

# ──────────────────────────────────────────
# Security Lists
# ──────────────────────────────────────────

# OKE API endpoint subnet
resource "oci_core_security_list" "oke_api" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "sl-oke-api"

  # API → workers (all)
  egress_security_rules {
    destination = "10.0.102.0/24"
    protocol    = "all"
  }

  # API → OCI services
  egress_security_rules {
    destination      = local.all_services.cidr_block
    destination_type = "SERVICE_CIDR_BLOCK"
    protocol         = "6"
    tcp_options {
      min = 443
      max = 443
    }
  }

  # External kubectl → API (6443): handled by NSG (allowed_cidr only)

  # workers → API (6443)
  ingress_security_rules {
    source   = "10.0.102.0/24"
    protocol = "6"
    tcp_options {
      min = 6443
      max = 6443
    }
  }

  # workers → API (12250 - OKE control plane)
  ingress_security_rules {
    source   = "10.0.102.0/24"
    protocol = "6"
    tcp_options {
      min = 12250
      max = 12250
    }
  }
}

# pub: LB subnet
resource "oci_core_security_list" "pub" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "sl-public"

  # LB → workers (NodePort range)
  egress_security_rules {
    destination = "10.0.102.0/24"
    protocol    = "6"
    tcp_options {
      min = 30000
      max = 32767
    }
  }

  # LB health check responses
  egress_security_rules {
    destination = "10.0.102.0/24"
    protocol    = "6"
    tcp_options {
      min = 10256
      max = 10256
    }
  }

  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "6"
    tcp_options {
      min = 443
      max = 443
    }
  }

  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "6"
    tcp_options {
      min = 80
      max = 80
    }
  }
}

# workers: OKE node pool
resource "oci_core_security_list" "workers" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "sl-workers"

  # workers → all (NAT outbound)
  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  # workers → OCI services
  egress_security_rules {
    destination      = local.all_services.cidr_block
    destination_type = "SERVICE_CIDR_BLOCK"
    protocol         = "all"
  }

  # workers → OKE API (6443)
  egress_security_rules {
    destination = "10.0.0.0/28"
    protocol    = "6"
    tcp_options {
      min = 6443
      max = 6443
    }
  }

  # workers → OKE API (12250)
  egress_security_rules {
    destination = "10.0.0.0/28"
    protocol    = "6"
    tcp_options {
      min = 12250
      max = 12250
    }
  }

  # workers → DB
  egress_security_rules {
    destination = "10.0.201.0/28"
    protocol    = "6"
    tcp_options {
      min = 3306
      max = 3306
    }
  }

  # worker ↔ worker (inter-Pod traffic, Flannel VXLAN)
  ingress_security_rules {
    source   = "10.0.102.0/24"
    protocol = "all"
  }

  # OKE API → workers (all)
  ingress_security_rules {
    source   = "10.0.0.0/28"
    protocol = "all"
  }

  # LB → worker NodePort range
  ingress_security_rules {
    source   = "10.0.1.0/28"
    protocol = "6"
    tcp_options {
      min = 30000
      max = 32767
    }
  }

  # LB health check
  ingress_security_rules {
    source   = "10.0.1.0/28"
    protocol = "6"
    tcp_options {
      min = 10256
      max = 10256
    }
  }

}

# db: ingress ← workers only (MySQL 3306)
resource "oci_core_security_list" "db" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "sl-db"

  # workers → DB
  ingress_security_rules {
    source   = "10.0.102.0/24"
    protocol = "6"
    tcp_options {
      min = 3306
      max = 3306
    }
  }

  # Allow response traffic (intra-VCN)
  egress_security_rules {
    destination = "10.0.0.0/16"
    protocol    = "6"
  }
}

# ──────────────────────────────────────────
# Subnets
# ──────────────────────────────────────────
resource "oci_core_subnet" "oke_api" {
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.main.id
  cidr_block        = "10.0.0.0/28"
  display_name      = "subnet-oke-api"
  dns_label         = "subokeapi"
  route_table_id    = oci_core_route_table.pub.id
  security_list_ids = [oci_core_security_list.oke_api.id]

  prohibit_public_ip_on_vnic = false
}

resource "oci_core_subnet" "pub" {
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.main.id
  cidr_block        = "10.0.1.0/28"
  display_name      = "subnet-public"
  dns_label         = "subpub"
  route_table_id    = oci_core_route_table.pub.id
  security_list_ids = [oci_core_security_list.pub.id]

  prohibit_public_ip_on_vnic = false
}

resource "oci_core_subnet" "workers" {
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.main.id
  cidr_block        = "10.0.102.0/24"
  display_name      = "subnet-workers"
  dns_label         = "subworkers"
  route_table_id    = oci_core_route_table.workers.id
  security_list_ids = [oci_core_security_list.workers.id]

  prohibit_public_ip_on_vnic = true
}

resource "oci_core_subnet" "db" {
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.main.id
  cidr_block        = "10.0.201.0/28"
  display_name      = "subnet-db"
  dns_label         = "subdb"
  route_table_id    = oci_core_route_table.db.id
  security_list_ids = [oci_core_security_list.db.id]

  prohibit_public_ip_on_vnic = true
}
