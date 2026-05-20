terraform {
  required_providers {
    oci = {
      source = "oracle/oci"
    }
  }
}

# ──────────────────────────────────────────
# Block Volume A (Vault + Prometheus + Jenkins)
# Always Free: 200GB total (boot included), min 50GB/vol
# Boot 2x47GB = 94GB used → ~106GB available for PV
# ──────────────────────────────────────────
resource "oci_core_volume" "block_a" {
  compartment_id      = var.compartment_ocid
  availability_domain = var.availability_domain
  display_name        = "bv-infra-a"
  size_in_gbs         = var.volume_a_size_in_gbs

  lifecycle {
    prevent_destroy = true
  }
}

# ──────────────────────────────────────────
# Block Volume B (Kafka + Redis + Tempo)
# ──────────────────────────────────────────
resource "oci_core_volume" "block_b" {
  compartment_id      = var.compartment_ocid
  availability_domain = var.availability_domain
  display_name        = "bv-infra-b"
  size_in_gbs         = var.volume_b_size_in_gbs

  lifecycle {
    prevent_destroy = true
  }
}
