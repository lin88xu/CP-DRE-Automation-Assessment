module "kong" {
  source = "../../modules/azure-single-host"

  name_prefix         = var.name_prefix
  location            = var.location
  resource_group_name = var.resource_group_name
  admin_username      = var.admin_username
  ssh_public_key_path = var.ssh_public_key_path
  vm_size             = var.vm_size
  admin_cidr          = var.admin_cidr
  vnet_cidr           = var.vnet_cidr
  subnet_cidr         = var.subnet_cidr
  os_disk_size_gb     = var.os_disk_size_gb
  kong_image          = var.kong_image
  postgres_image      = var.postgres_image
  proxy_port          = var.proxy_port
  admin_port          = var.admin_port
  manager_port        = var.manager_port
  app_host_header     = var.app_host_header
  upstream_url        = var.upstream_url
  tags                = var.tags
}

