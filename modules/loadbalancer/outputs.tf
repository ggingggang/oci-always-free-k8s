output "lb_id" {
  value = oci_load_balancer_load_balancer.main.id
}

output "lb_ip" {
  value = oci_load_balancer_load_balancer.main.ip_address_details[0].ip_address
}

output "backend_set_name" {
  value = oci_load_balancer_backend_set.http.name
}
