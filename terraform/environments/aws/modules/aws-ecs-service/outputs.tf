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
