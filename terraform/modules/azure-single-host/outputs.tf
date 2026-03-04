output "public_ip" {
  value       = azurerm_public_ip.this.ip_address
  description = "Public IP of the Kong host."
}

output "proxy_url" {
  value       = "http://${azurerm_public_ip.this.ip_address}:${var.proxy_port}"
  description = "Kong proxy URL."
}

output "admin_url" {
  value       = var.publish_admin_api ? "http://${azurerm_public_ip.this.ip_address}:${var.admin_port}" : null
  description = "Kong Admin API URL when public access is enabled."
}

output "manager_url" {
  value       = var.publish_manager_ui ? "http://${azurerm_public_ip.this.ip_address}:${var.manager_port}" : null
  description = "Kong Manager URL when public access is enabled."
}

output "ssh_command" {
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.this.ip_address}"
  description = "SSH command for the VM."
}
