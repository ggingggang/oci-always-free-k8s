output "unseal_key_id" {
  value       = oci_kms_key.openbao_unseal.id
  description = "OpenBao seal stanza: key_id"
}

output "crypto_endpoint" {
  value       = oci_kms_vault.main.crypto_endpoint
  description = "OpenBao seal stanza: crypto_endpoint"
}

output "management_endpoint" {
  value       = oci_kms_vault.main.management_endpoint
  description = "OpenBao seal stanza: management_endpoint"
}
