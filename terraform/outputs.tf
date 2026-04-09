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

output "heatwave_ip" {
  value = module.database.heatwave_ip
}

output "heatwave_port" {
  value = module.database.heatwave_port
}

