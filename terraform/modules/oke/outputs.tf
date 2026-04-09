output "cluster_id" {
  value = oci_containerengine_cluster.k8s.id
}

output "cluster_endpoint" {
  value = oci_containerengine_cluster.k8s.endpoints[0]["public_endpoint"]
}

output "node_pool_id" {
  value = oci_containerengine_node_pool.arm_workers.id
}
