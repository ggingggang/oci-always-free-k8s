output "nsg_public_id" {
  value       = oci_core_network_security_group.public_access.id
  description = "LB Service 어노테이션에 사용: oci-load-balancer-nsg-ids"
}
