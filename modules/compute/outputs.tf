output "master_instance_id" {
  value = oci_core_instance.master.id
}

output "master_private_ip" {
  value = oci_core_instance.master.private_ip
}

output "worker_pool_id" {
  value = oci_core_instance_pool.workers.id
}

output "worker_autoscaling_id" {
  value = oci_autoscaling_auto_scaling_configuration.workers.id
}
