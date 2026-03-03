output "proxy_url" {
  value       = module.kong.proxy_url
  description = "Kong proxy URL."
}

output "admin_url" {
  value       = module.kong.admin_url
  description = "Kong Admin API URL."
}

output "manager_url" {
  value       = module.kong.manager_url
  description = "Kong Manager UI URL."
}

output "route_test_command" {
  value       = module.kong.route_test_command
  description = "Sample command to verify routing."
}

