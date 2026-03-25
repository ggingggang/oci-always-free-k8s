terraform {
  required_providers {
    oci = {
      source = "oracle/oci"
    }
  }
}

# ──────────────────────────────────────────
# Dynamic Group - master (classic IAM)
# ──────────────────────────────────────────
# resource "oci_identity_dynamic_group" "master_vault" {
#   compartment_id = var.tenancy_ocid
#   name           = "dg-master-vault"
#   description    = "Master node instances with Vault write access"
#   matching_rule  = "ALL {instance.freeform_tag.role = 'master', instance.compartment.id = '${var.compartment_ocid}'}"
# }

# ──────────────────────────────────────────
# Dynamic Group - worker (classic IAM)
# ──────────────────────────────────────────
# resource "oci_identity_dynamic_group" "worker_vault" {
#   compartment_id = var.tenancy_ocid
#   name           = "dg-worker-vault"
#   description    = "Worker node instances with Vault read access"
#   matching_rule  = "ALL {instance.freeform_tag.role = 'worker', instance.compartment.id = '${var.compartment_ocid}'}"
# }

# ──────────────────────────────────────────
# Vault - kube-join-token
# ──────────────────────────────────────────
# resource "oci_kms_vault" "kube_join_token" {
#   compartment_id = var.compartment_ocid
#   display_name   = "kube-join-token"
#   vault_type     = "DEFAULT"
# }

# resource "oci_kms_key" "vault_key" {
#   compartment_id      = var.compartment_ocid
#   display_name        = "key-kube-join-token"
#   management_endpoint = oci_kms_vault.kube_join_token.management_endpoint
#
#   key_shape {
#     algorithm = "AES"
#     length    = 32
#   }
# }

# ──────────────────────────────────────────
# Policy - Vault permissions
# classic dynamic group referenced by name only
# ──────────────────────────────────────────
# resource "oci_identity_policy" "master_vault" {
#   compartment_id = var.tenancy_ocid
#   name           = "policy-master-vault"
#   description    = "Allow master nodes to write secrets to OCI Vault"
#
#   statements = [
#     "Allow dynamic-group ${oci_identity_dynamic_group.master_vault.name} to manage secret-family in tenancy",
#     "Allow dynamic-group ${oci_identity_dynamic_group.master_vault.name} to manage keys in tenancy",
#     "Allow dynamic-group ${oci_identity_dynamic_group.master_vault.name} to use vaults in tenancy",
#   ]
# }

# resource "oci_identity_policy" "worker_vault" {
#   compartment_id = var.tenancy_ocid
#   name           = "policy-worker-vault"
#   description    = "Allow worker nodes to read secrets from OCI Vault"
#
#   statements = [
#     "Allow dynamic-group ${oci_identity_dynamic_group.worker_vault.name} to read secret-family in tenancy",
#   ]
# }
