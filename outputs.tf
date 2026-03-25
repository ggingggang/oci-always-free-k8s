output "vcn_id" {
  value = module.networking.vcn_id
}

output "subnet_pub_id" {
  value = module.networking.subnet_pub_id
}

output "subnet_masters_id" {
  value = module.networking.subnet_masters_id
}

output "subnet_workers_id" {
  value = module.networking.subnet_workers_id
}

output "subnet_db_id" {
  value = module.networking.subnet_db_id
}

output "master_instance_id" {
  value = module.compute.master_instance_id
}

output "master_private_ip" {
  value = module.compute.master_private_ip
}

output "worker_pool_id" {
  value = module.compute.worker_pool_id
}

output "worker_autoscaling_id" {
  value = module.compute.worker_autoscaling_id
}

output "heatwave_ip" {
  value = module.database.heatwave_ip
}

output "heatwave_port" {
  value = module.database.heatwave_port
}

output "bastion_id" {
  value = module.networking.bastion_id
}

output "lb_ip" {
  value = module.loadbalancer.lb_ip
}
