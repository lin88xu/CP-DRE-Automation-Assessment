module "kong" {
  source = "../../modules/local-docker"

  docker_host     = var.docker_host
  name_prefix     = var.name_prefix
  kong_image      = var.kong_image
  postgres_image  = var.postgres_image
  proxy_port      = var.proxy_port
  admin_port      = var.admin_port
  manager_port    = var.manager_port
  db_port         = var.db_port
  app_host_header = var.app_host_header
  upstream_url    = var.upstream_url
}

