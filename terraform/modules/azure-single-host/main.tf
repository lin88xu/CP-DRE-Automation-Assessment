locals {
  docker_kong = templatefile("${path.module}/../../templates/docker-kong.yml.tftpl", {
    app_host_header = var.app_host_header
    upstream_url    = var.upstream_url
  })
}

resource "random_password" "kong_admin_gui_auth_secret" {
  length  = 64
  special = false
}

resource "random_password" "kong_admin_gui_session_secret" {
  length  = 64
  special = false
}

resource "random_password" "postgres_password" {
  length  = 32
  special = false
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "this" {
  name                = "${var.name_prefix}-vnet"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.vnet_cidr]
  tags                = var.tags
}

resource "azurerm_subnet" "this" {
  name                 = "${var.name_prefix}-subnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_cidr]
}

resource "azurerm_public_ip" "this" {
  name                = "${var.name_prefix}-pip"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_network_security_group" "this" {
  name                = "${var.name_prefix}-nsg"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags

  security_rule {
    name                       = "ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.admin_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "kong-proxy"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = tostring(var.proxy_port)
    source_address_prefix      = var.admin_cidr
    destination_address_prefix = "*"
  }

  dynamic "security_rule" {
    for_each = var.publish_admin_api ? [1] : []
    content {
      name                       = "kong-admin"
      priority                   = 120
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = tostring(var.admin_port)
      source_address_prefix      = var.admin_cidr
      destination_address_prefix = "*"
    }
  }

  dynamic "security_rule" {
    for_each = var.publish_manager_ui ? [1] : []
    content {
      name                       = "kong-manager"
      priority                   = 130
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = tostring(var.manager_port)
      source_address_prefix      = var.admin_cidr
      destination_address_prefix = "*"
    }
  }
}

resource "azurerm_network_interface" "this" {
  name                = "${var.name_prefix}-nic"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.this.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.this.id
  }
}

resource "azurerm_network_interface_security_group_association" "this" {
  network_interface_id      = azurerm_network_interface.this.id
  network_security_group_id = azurerm_network_security_group.this.id
}

resource "azurerm_linux_virtual_machine" "this" {
  name                = "${var.name_prefix}-vm"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  size                = var.vm_size
  admin_username      = var.admin_username
  network_interface_ids = [
    azurerm_network_interface.this.id,
  ]
  disable_password_authentication = true
  custom_data = base64encode(templatefile("${path.module}/../../templates/cloud-init-kong.sh.tftpl", {
    docker_compose = templatefile("${path.module}/../../templates/docker-compose.yml.tftpl", {
      name_prefix         = var.name_prefix
      kong_image          = var.kong_image
      postgres_image      = var.postgres_image
      public_host         = azurerm_public_ip.this.ip_address
      manager_public_host = var.publish_manager_ui ? azurerm_public_ip.this.ip_address : "127.0.0.1"
      proxy_port          = var.proxy_port
      admin_port          = var.admin_port
      manager_port        = var.manager_port
      proxy_bind_host     = "0.0.0.0"
      admin_bind_host     = var.publish_admin_api ? "0.0.0.0" : "127.0.0.1"
      manager_bind_host   = var.publish_manager_ui ? "0.0.0.0" : "127.0.0.1"
    })
    kong_env = templatefile("${path.module}/../../templates/kong.env.tftpl", {
      postgres_password      = random_password.postgres_password.result
      admin_gui_auth_conf    = jsonencode({ secret = random_password.kong_admin_gui_auth_secret.result })
      admin_gui_session_conf = jsonencode({ secret = random_password.kong_admin_gui_session_secret.result })
    })
    docker_kong = local.docker_kong
  }))

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.ssh_public_key_path)
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  tags = var.tags
}
