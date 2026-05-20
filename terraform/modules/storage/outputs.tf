output "volume_a_id" {
  value       = oci_core_volume.block_a.id
  description = "Block Volume A OCID (Vault + Prometheus + Jenkins)"
}

output "volume_b_id" {
  value       = oci_core_volume.block_b.id
  description = "Block Volume B OCID (Kafka + Redis + Tempo)"
}
