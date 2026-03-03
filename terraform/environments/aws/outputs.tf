output "alb_dns_name" {
  value       = module.kong.alb_dns_name
  description = "Public DNS name of the Kong load balancer."
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

output "ecs_cluster_name" {
  value       = module.kong.ecs_cluster_name
  description = "ECS cluster name."
}

output "ecs_service_name" {
  value       = module.kong.ecs_service_name
  description = "ECS service name."
}
