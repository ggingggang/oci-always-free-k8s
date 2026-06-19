terraform {
  required_providers {
    oci = {
      source = "oracle/oci"
    }
  }
}

data "oci_objectstorage_namespace" "ns" {
  compartment_id = var.compartment_ocid
}

# ──────────────────────────────────────────
# Buckets (Loki chunks 등 — bucket_names 로 확장)
# ──────────────────────────────────────────
resource "oci_objectstorage_bucket" "this" {
  for_each = toset(var.bucket_names)

  compartment_id = var.compartment_ocid
  namespace      = data.oci_objectstorage_namespace.ns.namespace
  name           = each.value
  access_type    = "NoPublicAccess"
  versioning     = "Disabled"
  storage_tier   = "Standard"
}
