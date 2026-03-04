output "alb_dns_name" {
  value       = aws_lb.this.dns_name
  description = "Public DNS name of the Kong load balancer."
}

output "proxy_url" {
  value       = "http://${aws_lb.this.dns_name}:${var.proxy_port}"
  description = "Kong proxy URL."
}

output "admin_url" {
  value       = "http://${aws_lb.this.dns_name}:${var.admin_port}"
  description = "Kong Admin API URL."
}

output "manager_url" {
  value       = "http://${aws_lb.this.dns_name}:${var.manager_port}"
  description = "Kong Manager URL."
}

output "ecs_cluster_name" {
  value       = aws_ecs_cluster.this.name
  description = "ECS cluster name."
}

output "ecs_service_name" {
  value       = aws_ecs_service.this.name
  description = "ECS service name."
}

output "amp_workspace_id" {
  value       = var.enable_managed_observability ? aws_prometheus_workspace.this[0].id : null
  description = "Amazon Managed Service for Prometheus workspace ID."
}

output "amp_workspace_arn" {
  value       = var.enable_managed_observability ? aws_prometheus_workspace.this[0].arn : null
  description = "Amazon Managed Service for Prometheus workspace ARN."
}

output "amp_prometheus_endpoint" {
  value       = var.enable_managed_observability ? aws_prometheus_workspace.this[0].prometheus_endpoint : null
  description = "Base query endpoint of the Amazon Managed Service for Prometheus workspace."
}

output "amp_remote_write_endpoint" {
  value       = var.enable_managed_observability ? "${aws_prometheus_workspace.this[0].prometheus_endpoint}api/v1/remote_write" : null
  description = "Remote write endpoint used by the ECS Prometheus collector sidecar."
}

output "grafana_workspace_id" {
  value       = var.enable_managed_observability ? aws_grafana_workspace.this[0].id : null
  description = "Amazon Managed Grafana workspace ID."
}

output "grafana_workspace_arn" {
  value       = var.enable_managed_observability ? aws_grafana_workspace.this[0].arn : null
  description = "Amazon Managed Grafana workspace ARN."
}

output "grafana_workspace_url" {
  value       = var.enable_managed_observability ? "https://${aws_grafana_workspace.this[0].endpoint}" : null
  description = "Amazon Managed Grafana workspace URL."
}

output "grafana_kong_dashboard_url" {
  value       = var.enable_managed_observability ? "https://${trimsuffix(aws_grafana_workspace.this[0].endpoint, "/")}/d/mY9p7dQmz" : null
  description = "Direct URL to the imported Kong official dashboard in Amazon Managed Grafana."
}
