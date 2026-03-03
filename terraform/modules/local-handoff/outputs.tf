output "inventory_file" {
  value       = local_file.ansible_inventory.filename
  description = "Generated Ansible inventory for the local host."
}

output "vars_file" {
  value       = local_file.ansible_vars.filename
  description = "Generated Terraform-to-Ansible variables file."
}

output "proxy_url" {
  value       = "http://${var.public_host}:${var.proxy_port}"
  description = "Expected Kong proxy URL after Ansible deployment."
}

output "admin_url" {
  value       = "http://${var.public_host}:${var.admin_port}"
  description = "Expected Kong Admin API URL after Ansible deployment."
}

output "manager_url" {
  value       = "http://${var.public_host}:${var.manager_port}"
  description = "Expected Kong Manager UI URL after Ansible deployment."
}

output "route_test_command" {
  value       = "curl -H 'Host: ${var.app_host_header}' http://${var.public_host}:${var.proxy_port}/get"
  description = "Sample command to verify routing after Ansible deployment."
}

output "ansible_deploy_command" {
  value       = "cd anisible && ANSIBLE_CONFIG=$PWD/ansible.cfg ansible-playbook -K -i ${local_file.ansible_inventory.filename} playbooks/site.yml -e @${local_file.ansible_vars.filename}"
  description = "Command to deploy the local stack with Ansible using Terraform-generated handoff files. In WSL on /mnt/c, ANSIBLE_CONFIG is set explicitly because ansible.cfg may otherwise be ignored."
}
