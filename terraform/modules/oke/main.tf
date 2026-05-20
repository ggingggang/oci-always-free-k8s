terraform {
  required_providers {
    oci = {
      source = "oracle/oci"
    }
  }
}

# ──────────────────────────────────────────
# OKE Cluster (Basic - Free Control Plane)
# Enhanced Cluster: $0.10/hr → Basic Cluster: $0.00
# Limitation: No virtual nodes, no add-ons, no control plane SLA
# ──────────────────────────────────────────
resource "oci_containerengine_cluster" "k8s" {
  compartment_id     = var.compartment_ocid
  kubernetes_version = var.kubernetes_version
  name               = "oke-cluster"
  vcn_id             = var.vcn_id
  type               = "BASIC_CLUSTER"

  endpoint_config {
    is_public_ip_enabled = true
    subnet_id            = var.subnet_oke_api_id
    nsg_ids              = var.endpoint_nsg_ids
  }

  cluster_pod_network_options {
    cni_type = "FLANNEL_OVERLAY"
  }

  options {
    service_lb_subnet_ids = [var.subnet_pub_id]

    kubernetes_network_config {
      pods_cidr     = "10.244.0.0/16"
      services_cidr = "10.96.0.0/16"
    }
  }
}

# ──────────────────────────────────────────
# Node Pool (ARM A1.Flex - Always Free)
# ──────────────────────────────────────────
data "local_file" "user_data" {
  filename = var.user_data_file
}

data "oci_core_images" "oke_arm" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Oracle Linux"
  operating_system_version = "8"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
  state                    = "AVAILABLE"

  filter {
    name   = "display_name"
    values = ["Oracle-Linux-8\\.\\d+-aarch64-.*"]
    regex  = true
  }
}

resource "oci_containerengine_node_pool" "arm_workers" {
  compartment_id     = var.compartment_ocid
  cluster_id         = oci_containerengine_cluster.k8s.id
  kubernetes_version = var.kubernetes_version
  name               = "pool-arm-workers"

  node_shape = "VM.Standard.A1.Flex"
  node_metadata = {
    user_data = base64encode(data.local_file.user_data.content)
  }
 
  node_shape_config {
    ocpus         = 2
    memory_in_gbs = 12
  }

  node_config_details {
    size = 2

    placement_configs {
      availability_domain = var.availability_domain
      subnet_id           = var.subnet_workers_id
    }
  }

  node_source_details {
    source_type = "IMAGE"
    image_id    = data.oci_core_images.oke_arm.images[0].id
  }

  initial_node_labels {
    key   = "pool"
    value = "arm-workers"
  }

  ssh_public_key = var.ssh_authorized_keys
}



