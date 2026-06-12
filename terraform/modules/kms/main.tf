terraform {
  required_providers {
    oci = {
      source = "oracle/oci"
    }
  }
}

# ──────────────────────────────────────────
# KMS Vault + auto-unseal Key
# ──────────────────────────────────────────
resource "oci_kms_vault" "main" {
  compartment_id = var.compartment_ocid
  display_name   = "vault-main"
  vault_type     = "DEFAULT"
}

# SOFTWARE protection: 과금 없음 (HSM 키 버전만 과금)
resource "oci_kms_key" "openbao_unseal" {
  compartment_id      = var.compartment_ocid
  display_name        = "openbao-unseal"
  management_endpoint = oci_kms_vault.main.management_endpoint
  protection_mode     = "SOFTWARE"

  key_shape {
    algorithm = "AES"
    length    = 32
  }
}
