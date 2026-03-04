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

output "amp_workspace_id" {
  value       = module.kong.amp_workspace_id
  description = "Amazon Managed Service for Prometheus workspace ID."
}

output "amp_workspace_arn" {
  value       = module.kong.amp_workspace_arn
  description = "Amazon Managed Service for Prometheus workspace ARN."
}

output "amp_prometheus_endpoint" {
  value       = module.kong.amp_prometheus_endpoint
  description = "Base query endpoint for the Amazon Managed Service for Prometheus workspace."
}

output "amp_remote_write_endpoint" {
  value       = module.kong.amp_remote_write_endpoint
  description = "Remote write endpoint used by the ECS Prometheus collector sidecar."
}

output "grafana_workspace_id" {
  value       = module.kong.grafana_workspace_id
  description = "Amazon Managed Grafana workspace ID."
}

output "grafana_workspace_arn" {
  value       = module.kong.grafana_workspace_arn
  description = "Amazon Managed Grafana workspace ARN."
}

output "disaster_recovery_rebuild_command" {
  value       = "bash ../../disaster-recovery.sh aws rebuild -- -var-file=terraform.tfvars"
  description = "Repository-native command to destroy and rebuild the AWS platform during a major outage."
}
