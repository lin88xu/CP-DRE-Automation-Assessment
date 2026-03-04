variable "name_prefix" {
  type        = string
  description = "Resource name prefix."
  default     = "kong-local"
}

variable "public_host" {
  type        = string
  description = "Public hostname used by local URLs and Kong Manager."
  default     = "localhost"
}

variable "kong_install_root" {
  type        = string
  description = "Install directory for the Kong compose stack."
  default     = "/opt/kong"
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

variable "observability_install_root" {
  type        = string
  description = "Install directory for Prometheus and Grafana."
  default     = "/opt/observability"
}

variable "observability_prometheus_port" {
  type        = number
  description = "Local host port mapped to Prometheus."
  default     = 9090
}

variable "observability_grafana_port" {
  type        = number
  description = "Local host port mapped to Grafana."
  default     = 3000
}

variable "observability_prometheus_image" {
  type        = string
  description = "Prometheus container image."
  default     = "prom/prometheus:v2.54.1"
}

variable "observability_grafana_image" {
  type        = string
  description = "Grafana container image."
  default     = "grafana/grafana:11.1.3"
}

variable "observability_grafana_admin_user" {
  type        = string
  description = "Grafana admin username."
  default     = ""
}

variable "observability_grafana_admin_password" {
  type        = string
  description = "Grafana admin password."
  default     = ""
}

variable "observability_scrape_host" {
  type        = string
  description = "Host used by Prometheus to scrape Kong metrics."
  default     = "host.docker.internal"
}

variable "observability_kong_job_name" {
  type        = string
  description = "Prometheus job name for Kong."
  default     = "kong-admin"
}
