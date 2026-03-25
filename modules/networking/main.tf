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

resource "oci_core_route_table" "masters" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "rt-masters"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.nat.id
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
}

resource "oci_core_route_table" "db" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "rt-db"
}

# ──────────────────────────────────────────
# Security Lists
# ──────────────────────────────────────────

# pub: egress → masters only
resource "oci_core_security_list" "pub" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "sl-public"

  egress_security_rules {
    destination = "10.0.101.0/28"
    protocol    = "all"
  }

  # LB → workers (NodePort)
  egress_security_rules {
    destination = "10.0.102.0/24"
    protocol    = "6"
    tcp_options {
      min = 30080
      max = 30080
    }
  }

  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "6" # TCP
    tcp_options {
      max = 443
      min = 443
    }
  }

  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "6"
    tcp_options {
      max = 80
      min = 80
    }
  }
}

# masters: egress → workers + db, ingress ← pub + workers
resource "oci_core_security_list" "masters" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "sl-masters"

  egress_security_rules {
    destination = "10.0.102.0/24"
    protocol    = "all"
  }

  egress_security_rules {
    destination = "10.0.201.0/28"
    protocol    = "all"
  }

  # Allow outbound via NAT
  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  ingress_security_rules {
    source   = "10.0.1.0/28"
    protocol = "all"
  }

  # workers → masters (kubelet → API server)
  ingress_security_rules {
    source   = "10.0.102.0/24"
    protocol = "all"
  }

  # Bastion → master SSH (Bastion accesses within masters subnet)
  ingress_security_rules {
    source   = "10.0.101.0/28"
    protocol = "6"
    tcp_options {
      min = 22
      max = 22
    }
  }
}

# workers: egress → masters + db, ingress ← masters + pub(LB)
resource "oci_core_security_list" "workers" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "sl-workers"

  # workers → masters (kubelet → API server)
  egress_security_rules {
    destination = "10.0.101.0/28"
    protocol    = "all"
  }

  egress_security_rules {
    destination = "10.0.201.0/28"
    protocol    = "all"
  }

  # Allow outbound via NAT
  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  ingress_security_rules {
    source   = "10.0.101.0/28"
    protocol = "all"
  }

  # worker ↔ worker (inter-Pod traffic)
  ingress_security_rules {
    source   = "10.0.102.0/24"
    protocol = "all"
  }

  # LB(pub subnet) → worker NodePort
  ingress_security_rules {
    source   = "10.0.1.0/28"
    protocol = "6"
    tcp_options {
      min = 30080
      max = 30080
    }
  }
}

# db: ingress ← masters + workers (MySQL 3306 only)
resource "oci_core_security_list" "db" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "sl-db"

  # masters → DB
  ingress_security_rules {
    source   = "10.0.101.0/28"
    protocol = "6"
    tcp_options {
      min = 3306
      max = 3306
    }
  }

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

resource "oci_core_subnet" "masters" {
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.main.id
  cidr_block        = "10.0.101.0/28"
  display_name      = "subnet-masters"
  dns_label         = "submasters"
  route_table_id    = oci_core_route_table.masters.id
  security_list_ids = [oci_core_security_list.masters.id]

  prohibit_public_ip_on_vnic = true
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

# ──────────────────────────────────────────
# Bastion
# ──────────────────────────────────────────
resource "oci_bastion_bastion" "main" {
  compartment_id               = var.compartment_ocid
  bastion_type                 = "STANDARD"
  target_subnet_id             = oci_core_subnet.masters.id
  name                         = "bastion-main"
  client_cidr_block_allow_list = var.bastion_allowed_cidrs
}
