variable "name_prefix" {
  type        = string
  description = "Resource name prefix passed to Ansible."
}

variable "public_host" {
  type        = string
  description = "Public hostname exposed by the local deployment."
}

variable "kong_install_root" {
  type        = string
  description = "Install directory for the Kong compose stack."
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
  description = "Local host port reserved for PostgreSQL."
}

variable "app_host_header" {
  type        = string
  description = "Host header used by the sample Kong route."
}

variable "upstream_url" {
  type        = string
  description = "Upstream URL used by the sample route."
}

variable "observability_install_root" {
  type        = string
  description = "Install directory for Prometheus and Grafana."
}

variable "observability_prometheus_port" {
  type        = number
  description = "Local host port mapped to Prometheus."
}

variable "observability_grafana_port" {
  type        = number
  description = "Local host port mapped to Grafana."
}

variable "observability_prometheus_image" {
  type        = string
  description = "Prometheus container image."
}

variable "observability_grafana_image" {
  type        = string
  description = "Grafana container image."
}

variable "observability_grafana_admin_user" {
  type        = string
  description = "Grafana admin username."
}

variable "observability_grafana_admin_password" {
  type        = string
  description = "Grafana admin password."
}

variable "observability_scrape_host" {
  type        = string
  description = "Host used by Prometheus to scrape Kong metrics."
}

variable "observability_kong_job_name" {
  type        = string
  description = "Prometheus job name for Kong."
}
