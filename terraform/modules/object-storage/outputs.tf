output "namespace" {
  value       = data.oci_objectstorage_namespace.ns.namespace
  description = "Object Storage namespace"
}

output "s3_endpoint" {
  value       = "https://${data.oci_objectstorage_namespace.ns.namespace}.compat.objectstorage.${var.region}.oraclecloud.com"
  description = "S3-compatible endpoint (Loki/Velero storage_config)"
}

output "bucket_names" {
  value = [for b in oci_objectstorage_bucket.this : b.name]
}
