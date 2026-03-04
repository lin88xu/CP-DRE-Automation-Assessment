variable "subscription_id" {
  type        = string
  description = "Azure subscription ID."
}

variable "location" {
  type        = string
  description = "Azure region."
  default     = "Southeast Asia"
}

variable "name_prefix" {
  type        = string
  description = "Resource name prefix."
  default     = "kong-azure"
}

variable "resource_group_name" {
  type        = string
  description = "Azure resource group name."
  default     = "rg-kong-assessment"
}

variable "admin_username" {
  type        = string
  description = "Admin username for the VM."
  default     = "azureuser"
}

variable "ssh_public_key_path" {
  type        = string
  description = "Path to the public SSH key used for VM access."
}

variable "vm_size" {
  type        = string
  description = "Azure VM size."
  default     = "Standard_B2s"
}

variable "admin_cidr" {
  type        = string
  description = "CIDR allowed to reach SSH and any published management ports."
  default     = "203.0.113.10/32"
}

variable "vnet_cidr" {
  type        = string
  description = "Address space for the virtual network."
  default     = "10.30.0.0/16"
}

variable "subnet_cidr" {
  type        = string
  description = "Address prefix for the subnet."
  default     = "10.30.1.0/24"
}

variable "os_disk_size_gb" {
  type        = number
  description = "OS disk size in GB."
  default     = 30
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
  description = "Whether to publish the Kong Admin API on the VM public IP."
  default     = false
}

variable "publish_manager_ui" {
  type        = bool
  description = "Whether to publish the Kong Manager UI on the VM public IP."
  default     = false
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

variable "tags" {
  type        = map(string)
  description = "Tags applied to Azure resources."
  default = {
    project = "cp-dre-assessment"
    stack   = "kong"
  }
}
