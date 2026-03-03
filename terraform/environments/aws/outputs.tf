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

output "grafana_workspace_url" {
  value       = module.kong.grafana_workspace_url
  description = "Amazon Managed Grafana workspace URL."
}

output "grafana_kong_dashboard_url" {
  value       = module.kong.grafana_kong_dashboard_url
  description = "Direct URL to the imported Kong official dashboard in Amazon Managed Grafana."
}
