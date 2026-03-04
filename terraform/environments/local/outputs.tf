output "inventory_file" {
  value       = module.kong.inventory_file
  description = "Terraform-generated Ansible inventory for the local host."
}

output "vars_file" {
  value       = module.kong.vars_file
  description = "Terraform-generated variables file for the Ansible local deployment."
}

output "ansible_deploy_command" {
  value       = module.kong.ansible_deploy_command
  description = "Command to deploy Kong and observability locally with Ansible."
}

output "proxy_url" {
  value       = module.kong.proxy_url
  description = "Expected Kong proxy URL after Ansible deployment."
}

output "admin_url" {
  value       = module.kong.admin_url
  description = "Expected Kong Admin API URL after Ansible deployment."
}

output "manager_url" {
  value       = module.kong.manager_url
  description = "Expected Kong Manager UI URL after Ansible deployment."
}

output "route_test_command" {
  value       = module.kong.route_test_command
  description = "Sample command to verify routing after Ansible deployment."
}
