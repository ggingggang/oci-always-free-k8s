output "vcn_id" {
  value = module.networking.vcn_id
}

output "subnet_oke_api_id" {
  value = module.networking.subnet_oke_api_id
}

output "subnet_pub_id" {
  value = module.networking.subnet_pub_id
}

output "subnet_workers_id" {
  value = module.networking.subnet_workers_id
}

output "subnet_db_id" {
  value = module.networking.subnet_db_id
}

output "oke_cluster_id" {
  value = module.oke.cluster_id
}

output "oke_cluster_endpoint" {
  value = module.oke.cluster_endpoint
}

output "oke_node_pool_id" {
  value = module.oke.node_pool_id
}

output "nsg_public_id" {
  value       = module.iam.nsg_public_id
  description = "NSG OCID for LB annotation (oci-load-balancer-nsg-ids)"
}

output "heatwave_ip" {
  value = module.database.heatwave_ip
}

output "heatwave_port" {
  value = module.database.heatwave_port
}

output "kms_unseal_key_id" {
  value       = module.kms.unseal_key_id
  description = "OpenBao seal stanza: key_id"
}

output "kms_crypto_endpoint" {
  value       = module.kms.crypto_endpoint
  description = "OpenBao seal stanza: crypto_endpoint"
}

output "kms_management_endpoint" {
  value       = module.kms.management_endpoint
  description = "OpenBao seal stanza: management_endpoint"
}

output "object_storage_namespace" {
  value       = module.object_storage.namespace
  description = "Loki storage_config / S3 endpoint 구성용"
}

output "object_storage_s3_endpoint" {
  value       = module.object_storage.s3_endpoint
  description = "Loki S3-compat endpoint"
}

output "object_storage_buckets" {
  value = module.object_storage.bucket_names
}

