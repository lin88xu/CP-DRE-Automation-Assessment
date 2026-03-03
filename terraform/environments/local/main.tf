module "kong" {
  source = "../../modules/local-handoff"

  name_prefix                          = var.name_prefix
  public_host                          = var.public_host
  kong_install_root                    = var.kong_install_root
  kong_image                           = var.kong_image
  postgres_image                       = var.postgres_image
  proxy_port                           = var.proxy_port
  admin_port                           = var.admin_port
  manager_port                         = var.manager_port
  db_port                              = var.db_port
  app_host_header                      = var.app_host_header
  upstream_url                         = var.upstream_url
  observability_install_root           = var.observability_install_root
  observability_prometheus_port        = var.observability_prometheus_port
  observability_grafana_port           = var.observability_grafana_port
  observability_prometheus_image       = var.observability_prometheus_image
  observability_grafana_image          = var.observability_grafana_image
  observability_grafana_admin_user     = var.observability_grafana_admin_user
  observability_grafana_admin_password = var.observability_grafana_admin_password
  observability_scrape_host            = var.observability_scrape_host
  observability_kong_job_name          = var.observability_kong_job_name
}
