output "vcn_id" {
  value = oci_core_vcn.main.id
}

output "subnet_oke_api_id" {
  value = oci_core_subnet.oke_api.id
}

output "subnet_pub_id" {
  value = oci_core_subnet.pub.id
}

output "subnet_workers_id" {
  value = oci_core_subnet.workers.id
}

output "subnet_db_id" {
  value = oci_core_subnet.db.id
}

