output "public_ip" {
  value       = module.kong.public_ip
  description = "Public IP of the Kong host."
}

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
  description = "Kong Manager URL."
}

output "ssh_command" {
  value       = module.kong.ssh_command
  description = "SSH command for the VM."
}

