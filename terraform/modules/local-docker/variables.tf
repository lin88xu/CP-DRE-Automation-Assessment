variable "docker_host" {
  type        = string
  description = "Docker daemon socket or TCP endpoint."
}

variable "name_prefix" {
  type        = string
  description = "Resource name prefix."
}

variable "kong_image" {
  type        = string
  description = "Kong container image."
}

variable "postgres_image" {
  type        = string
  description = "PostgreSQL container image."
}

variable "proxy_port" {
  type        = number
  description = "Local host port mapped to the Kong proxy."
}

variable "admin_port" {
  type        = number
  description = "Local host port mapped to the Kong Admin API."
}

variable "manager_port" {
  type        = number
  description = "Local host port mapped to the Kong Manager UI."
}

variable "db_port" {
  type        = number
  description = "Local host port mapped to PostgreSQL."
}

variable "app_host_header" {
  type        = string
  description = "Host header used by the sample Kong route."
}

variable "upstream_url" {
  type        = string
  description = "Upstream URL used by the sample route."
}

