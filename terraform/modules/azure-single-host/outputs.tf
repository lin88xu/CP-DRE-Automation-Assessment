output "public_ip" {
  value       = azurerm_public_ip.this.ip_address
  description = "Public IP of the Kong host."
}

output "proxy_url" {
  value       = "http://${azurerm_public_ip.this.ip_address}:${var.proxy_port}"
  description = "Kong proxy URL."
}

output "admin_url" {
  value       = "http://${azurerm_public_ip.this.ip_address}:${var.admin_port}"
  description = "Kong Admin API URL."
}

output "manager_url" {
  value       = "http://${azurerm_public_ip.this.ip_address}:${var.manager_port}"
  description = "Kong Manager URL."
}

output "ssh_command" {
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.this.ip_address}"
  description = "SSH command for the VM."
}

