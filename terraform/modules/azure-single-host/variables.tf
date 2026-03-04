variable "name_prefix" {
  type        = string
  description = "Resource name prefix."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "resource_group_name" {
  type        = string
  description = "Azure resource group name."
}

variable "admin_username" {
  type        = string
  description = "Admin username for the VM."
}

variable "ssh_public_key_path" {
  type        = string
  description = "Path to the public SSH key used for VM access."
}

variable "vm_size" {
  type        = string
  description = "Azure VM size."
}

variable "admin_cidr" {
  type        = string
  description = "CIDR allowed to reach SSH and Kong ports."
}

variable "vnet_cidr" {
  type        = string
  description = "Address space for the virtual network."
}

variable "subnet_cidr" {
  type        = string
  description = "Address prefix for the subnet."
}

variable "os_disk_size_gb" {
  type        = number
  description = "OS disk size in GB."
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
  description = "Tags applied to Azure resources."
  default     = {}
}

