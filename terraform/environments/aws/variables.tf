variable "aws_region" {
  type        = string
  description = "AWS region for the deployment."
  default     = "ap-southeast-1"
}

variable "availability_zone" {
  type        = string
  description = "Preferred availability zone. Leave empty to use the first two available zones."
  default     = ""
}

variable "name_prefix" {
  type        = string
  description = "Resource name prefix."
  default     = "kong-aws"
}

variable "admin_cidr" {
  type        = string
  description = "CIDR allowed to reach published management ports when they are enabled."
  default     = "203.0.113.10/32"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC."
  default     = "10.20.0.0/16"
}

variable "subnet_cidr" {
  type        = string
  description = "CIDR block for the first public subnet."
  default     = "10.20.1.0/24"
}

variable "secondary_subnet_cidr" {
  type        = string
  description = "CIDR block for the second public subnet used by the ALB and ECS service."
  default     = "10.20.2.0/24"
}

variable "kong_image" {
  type        = string
  description = "Kong container image."
  default     = "kong:latest"
}

variable "postgres_image" {
  type        = string
  description = "PostgreSQL container image used for the task-local Kong database."
  default     = "postgres:15-alpine"
}

variable "proxy_port" {
  type        = number
  description = "Public port mapped to the Kong proxy."
  default     = 8000
}

variable "admin_port" {
  type        = number
  description = "Public port mapped to the Kong Admin API."
  default     = 8001
}

variable "manager_port" {
  type        = number
  description = "Public port mapped to the Kong Manager UI."
  default     = 8002
}

variable "publish_admin_api" {
  type        = bool
  description = "Whether to publish the Kong Admin API through the ALB."
  default     = false
}

variable "publish_manager_ui" {
  type        = bool
  description = "Whether to publish the Kong Manager UI through the ALB."
  default     = false
}

variable "desired_count" {
  type        = number
  description = "Desired ECS task count."
  default     = 1
}

variable "min_capacity" {
  type        = number
  description = "Minimum number of ECS tasks maintained by autoscaling."
  default     = 1
}

variable "max_capacity" {
  type        = number
  description = "Maximum number of ECS tasks allowed by autoscaling."
  default     = 4
}

variable "task_cpu" {
  type        = number
  description = "Fargate task CPU units."
  default     = 1024
}

variable "task_memory" {
  type        = number
  description = "Fargate task memory in MiB."
  default     = 2048
}

variable "cpu_target_value" {
  type        = number
  description = "Target average ECS service CPU utilization percentage."
  default     = 60
}

variable "memory_target_value" {
  type        = number
  description = "Target average ECS service memory utilization percentage."
  default     = 70
}

variable "requests_target_value" {
  type        = number
  description = "Target ALB requests per target for the Kong proxy listener."
  default     = 1000
}

variable "scale_in_cooldown" {
  type        = number
  description = "Cooldown in seconds before scaling in again."
  default     = 120
}

variable "scale_out_cooldown" {
  type        = number
  description = "Cooldown in seconds before scaling out again."
  default     = 60
}

variable "app_host_header" {
  type        = string
  description = "Host header used by the sample Kong route."
  default     = "example.com"
}

variable "upstream_url" {
  type        = string
  description = "Upstream URL used by the sample route."
  default     = "http://httpbin.org"
}

variable "enable_managed_observability" {
  type        = bool
  description = "Whether to provision Amazon Managed Service for Prometheus and Amazon Managed Grafana for the AWS target."
  default     = true
}

variable "observability_prometheus_image" {
  type        = string
  description = "Prometheus image used by the ECS sidecar that scrapes Kong and remote-writes to AMP."
  default     = "prom/prometheus:v2.54.1"
}

variable "observability_kong_job_name" {
  type        = string
  description = "Prometheus job name used for Kong metrics in the AWS managed observability stack."
  default     = "kong-admin"
}

variable "observability_scrape_interval" {
  type        = string
  description = "Prometheus scrape and evaluation interval for the ECS metrics collector."
  default     = "10s"
}

variable "grafana_admin_user_ids" {
  type        = list(string)
  description = "IAM Identity Center user IDs to assign the Admin role in the Amazon Managed Grafana workspace."
  default     = []
}

variable "grafana_editor_user_ids" {
  type        = list(string)
  description = "IAM Identity Center user IDs to assign the Editor role in the Amazon Managed Grafana workspace."
  default     = []
}

variable "grafana_viewer_user_ids" {
  type        = list(string)
  description = "IAM Identity Center user IDs to assign the Viewer role in the Amazon Managed Grafana workspace."
  default     = []
}

variable "grafana_admin_group_ids" {
  type        = list(string)
  description = "IAM Identity Center group IDs to assign the Admin role in the Amazon Managed Grafana workspace."
  default     = []
}

variable "grafana_editor_group_ids" {
  type        = list(string)
  description = "IAM Identity Center group IDs to assign the Editor role in the Amazon Managed Grafana workspace."
  default     = []
}

variable "grafana_viewer_group_ids" {
  type        = list(string)
  description = "IAM Identity Center group IDs to assign the Viewer role in the Amazon Managed Grafana workspace."
  default     = []
}

variable "enable_grafana_dashboard_bootstrap" {
  type        = bool
  description = "Whether Terraform should create the AMP data source and import the official Kong dashboard into Amazon Managed Grafana."
  default     = true
}

variable "grafana_dashboard_service_account_token_ttl" {
  type        = number
  description = "Lifetime in seconds for the temporary AMG service account token used to bootstrap the dashboard and data source."
  default     = 14400
}

variable "grafana_prometheus_datasource_name" {
  type        = string
  description = "Datasource name created in Amazon Managed Grafana for querying the AMP workspace."
  default     = "Amazon Managed Service for Prometheus"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to AWS resources."
  default = {
    project = "cp-dre-assessment"
    stack   = "kong"
  }
}
