variable "name_prefix" {
  type        = string
  description = "Resource name prefix."
}

variable "availability_zone" {
  type        = string
  description = "Preferred AWS availability zone. Leave empty to use the first two available zones."
  default     = ""
}

variable "admin_cidr" {
  type        = string
  description = "CIDR allowed to reach the Kong load balancer ports."
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC."
}

variable "subnet_cidr" {
  type        = string
  description = "CIDR block for the first public subnet."
}

variable "secondary_subnet_cidr" {
  type        = string
  description = "CIDR block for the second public subnet used by the ALB and ECS service."
}

variable "kong_image" {
  type        = string
  description = "Kong container image."
}

variable "proxy_port" {
  type        = number
  description = "Public port mapped to the Kong proxy."
}

variable "admin_port" {
  type        = number
  description = "Public port mapped to the Kong Admin API."
}

variable "manager_port" {
  type        = number
  description = "Public port mapped to the Kong Manager UI."
}

variable "desired_count" {
  type        = number
  description = "Desired ECS task count."
}

variable "min_capacity" {
  type        = number
  description = "Minimum number of ECS tasks maintained by autoscaling."
}

variable "max_capacity" {
  type        = number
  description = "Maximum number of ECS tasks allowed by autoscaling."
}

variable "task_cpu" {
  type        = number
  description = "Fargate task CPU units."
}

variable "task_memory" {
  type        = number
  description = "Fargate task memory in MiB."
}

variable "cpu_target_value" {
  type        = number
  description = "Target average ECS service CPU utilization percentage."
}

variable "memory_target_value" {
  type        = number
  description = "Target average ECS service memory utilization percentage."
}

variable "requests_target_value" {
  type        = number
  description = "Target ALB requests per target for the Kong proxy listener."
}

variable "scale_in_cooldown" {
  type        = number
  description = "Cooldown in seconds before scaling in again."
}

variable "scale_out_cooldown" {
  type        = number
  description = "Cooldown in seconds before scaling out again."
}

variable "app_host_header" {
  type        = string
  description = "Host header used by the sample Kong route."
}

variable "upstream_url" {
  type        = string
  description = "Upstream URL used by the sample route."
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to AWS resources."
  default     = {}
}
