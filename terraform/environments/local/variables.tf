variable "docker_host" {
  type        = string
  description = "Docker daemon socket or TCP endpoint."
  default     = "unix:///var/run/docker.sock"
}

variable "name_prefix" {
  type        = string
  description = "Resource name prefix."
  default     = "kong-local"
}

variable "kong_image" {
  type        = string
  description = "Kong container image."
  default     = "kong:latest"
}

variable "postgres_image" {
  type        = string
  description = "PostgreSQL container image."
  default     = "postgres:15-alpine"
}

variable "proxy_port" {
  type        = number
  description = "Local host port mapped to the Kong proxy."
  default     = 8000
}

variable "admin_port" {
  type        = number
  description = "Local host port mapped to the Kong Admin API."
  default     = 8001
}

variable "manager_port" {
  type        = number
  description = "Local host port mapped to the Kong Manager UI."
  default     = 8002
}

variable "db_port" {
  type        = number
  description = "Local host port mapped to PostgreSQL."
  default     = 5432
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

