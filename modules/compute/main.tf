terraform {
  required_providers {
    oci = {
      source = "oracle/oci"
    }
    tls = {
      source = "hashicorp/tls"
    }
  }
}

# ──────────────────────────────────────────
# SSH Key (master → worker access)
# ──────────────────────────────────────────
resource "tls_private_key" "master_ssh" {
  algorithm = "ED25519"
}

# Rocky Linux 9 (Community Edition, aarch64)
# Marketplace image — cannot query via data source, OCID specified directly

# ──────────────────────────────────────────
# Master Node
# ──────────────────────────────────────────
resource "oci_core_instance" "master" {
  compartment_id      = var.compartment_ocid
  display_name        = "master-01"
  availability_domain = var.availability_domain
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = 1
    memory_in_gbs = 6
  }

  source_details {
    source_type = "image"
    source_id   = var.image_id
  }

  create_vnic_details {
    subnet_id        = var.subnet_masters_id
    assign_public_ip = false
  }

  agent_config {
    are_all_plugins_disabled = false
    is_management_disabled   = false
    is_monitoring_disabled   = false

    plugins_config {
      name          = "Bastion"
      desired_state = "ENABLED"
    }
  }

  metadata = {
    ssh_authorized_keys = var.ssh_authorized_keys
    user_data           = base64encode(templatefile("${path.root}/scripts/cloud-init-master.sh", {
      kubernetes_version = "1.35"
      pod_cidr           = "192.168.0.0/16"
      ssh_private_key    = trimspace(tls_private_key.master_ssh.private_key_openssh)
      worker_subnet_cidr = var.worker_subnet_cidr
    }))
  }

  freeform_tags = {
    role = "master"
  }
}

# ──────────────────────────────────────────
# Worker Instance Configuration (template)
# ──────────────────────────────────────────
resource "oci_core_instance_configuration" "worker" {
  compartment_id = var.compartment_ocid
  display_name   = "ic-worker"

  instance_details {
    instance_type = "compute"

    launch_details {
      compartment_id = var.compartment_ocid
      shape          = "VM.Standard.A1.Flex"

      shape_config {
        ocpus         = 1
        memory_in_gbs = 6
      }

      source_details {
        source_type = "image"
        image_id    = var.image_id
      }

      create_vnic_details {
        subnet_id        = var.subnet_workers_id
        assign_public_ip = false
      }

      metadata = {
        ssh_authorized_keys = var.ssh_authorized_keys
        user_data           = base64encode(templatefile("${path.root}/scripts/cloud-init-worker.sh", {
          kubernetes_version = "1.35"
          master_ssh_pubkey  = trimspace(tls_private_key.master_ssh.public_key_openssh)
        }))
      }

      freeform_tags = {
        role = "worker"
      }
    }
  }
}

# ──────────────────────────────────────────
# Worker Instance Pool
# ──────────────────────────────────────────
resource "oci_core_instance_pool" "workers" {
  compartment_id            = var.compartment_ocid
  display_name              = "pool-workers"
  instance_configuration_id = oci_core_instance_configuration.worker.id
  size                      = 2

  depends_on = [oci_core_instance.master]

  lifecycle {
    ignore_changes = [size]
  }

  placement_configurations {
    availability_domain = var.availability_domain
    primary_subnet_id   = var.subnet_workers_id
  }

  load_balancers {
    load_balancer_id = var.lb_id
    backend_set_name = var.lb_backend_set_name
    port             = 30080
    vnic_selection   = "PrimaryVnic"
  }
}

# ──────────────────────────────────────────
# Autoscaling Configuration (CPU-based)
# ──────────────────────────────────────────
resource "oci_autoscaling_auto_scaling_configuration" "workers" {
  compartment_id = var.compartment_ocid
  display_name   = "asc-workers"
  is_enabled     = true

  policies {
    display_name = "asc-policy-workers"
    policy_type  = "threshold"

    capacity {
      initial = 2
      min     = 2
      max     = 3
    }

    rules {
      display_name = "scale-out"
      action {
        type  = "CHANGE_COUNT_BY"
        value = 1
      }
      metric {
        metric_type = "CPU_UTILIZATION"
        threshold {
          operator = "GT"
          value    = 70
        }
      }
    }

    rules {
      display_name = "scale-in"
      action {
        type  = "CHANGE_COUNT_BY"
        value = -1
      }
      metric {
        metric_type = "CPU_UTILIZATION"
        threshold {
          operator = "LT"
          value    = 30
        }
      }
    }
  }

  auto_scaling_resources {
    id   = oci_core_instance_pool.workers.id
    type = "instancePool"
  }
}
