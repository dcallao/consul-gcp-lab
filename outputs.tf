# ---------------------------------------------------------------------------------------------------------------------
# Consul Demo Server Outputs
# ---------------------------------------------------------------------------------------------------------------------
output "Consul_Server_Public_IP" {
  value = google_compute_instance.consul.0.network_interface.0.access_config.0.nat_ip
}

output "Consul_Server_HTTP_Address" {
  value = "http://${google_compute_instance.consul.0.network_interface.0.access_config.0.nat_ip}:8500"
}
