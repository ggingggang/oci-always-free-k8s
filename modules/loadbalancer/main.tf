terraform {
  required_providers {
    oci = {
      source = "oracle/oci"
    }
  }
}

# ──────────────────────────────────────────
# Load Balancer (Always Free - 10Mbps)
# ──────────────────────────────────────────
resource "oci_load_balancer_load_balancer" "main" {
  compartment_id = var.compartment_ocid
  display_name   = "lb-main"
  shape          = "flexible"
  subnet_ids     = [var.subnet_pub_id]
  is_private     = false

  shape_details {
    minimum_bandwidth_in_mbps = 10
    maximum_bandwidth_in_mbps = 10
  }
}

# ──────────────────────────────────────────
# Backend Set
# ──────────────────────────────────────────
resource "oci_load_balancer_backend_set" "http" {
  load_balancer_id = oci_load_balancer_load_balancer.main.id
  name             = "bs-http"
  policy           = "ROUND_ROBIN"

  health_checker {
    protocol          = "TCP"
    port              = 30080
    interval_ms       = 10000
    timeout_in_millis = 3000
    retries           = 3
  }
}

# ──────────────────────────────────────────
# Listener - HTTP (80)
# ──────────────────────────────────────────
resource "oci_load_balancer_listener" "http" {
  load_balancer_id         = oci_load_balancer_load_balancer.main.id
  name                     = "listener-http"
  default_backend_set_name = oci_load_balancer_backend_set.http.name
  port                     = 80
  protocol                 = "HTTP"
}
