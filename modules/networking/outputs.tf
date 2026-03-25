output "vcn_id" {
  value = oci_core_vcn.main.id
}

output "subnet_pub_id" {
  value = oci_core_subnet.pub.id
}

output "subnet_masters_id" {
  value = oci_core_subnet.masters.id
}

output "subnet_workers_id" {
  value = oci_core_subnet.workers.id
}

output "subnet_db_id" {
  value = oci_core_subnet.db.id
}

output "bastion_id" {
  value = oci_bastion_bastion.main.id
}

output "bastion_endpoint" {
  value = oci_bastion_bastion.main.private_endpoint_ip_address
}
