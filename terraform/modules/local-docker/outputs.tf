output "proxy_url" {
  value       = "http://localhost:${var.proxy_port}"
  description = "Kong proxy URL."
}

output "admin_url" {
  value       = "http://localhost:${var.admin_port}"
  description = "Kong Admin API URL."
}

output "manager_url" {
  value       = "http://localhost:${var.manager_port}"
  description = "Kong Manager UI URL."
}

output "route_test_command" {
  value       = "curl -H 'Host: ${var.app_host_header}' http://localhost:${var.proxy_port}/"
  description = "Sample command to verify routing."
}

