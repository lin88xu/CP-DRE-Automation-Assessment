module "kong" {
  # Keep the AWS environment self-contained so HCP Terraform CLI-driven runs
  # can resolve the module source even when this directory is uploaded alone.
  source = "./modules/aws-ecs-service"

  name_prefix                                 = var.name_prefix
  availability_zone                           = var.availability_zone
  admin_cidr                                  = var.admin_cidr
  vpc_cidr                                    = var.vpc_cidr
  subnet_cidr                                 = var.subnet_cidr
  secondary_subnet_cidr                       = var.secondary_subnet_cidr
  kong_image                                  = var.kong_image
  postgres_image                              = var.postgres_image
  proxy_port                                  = var.proxy_port
  admin_port                                  = var.admin_port
  manager_port                                = var.manager_port
  publish_admin_api                           = var.publish_admin_api
  publish_manager_ui                          = var.publish_manager_ui
  desired_count                               = var.desired_count
  min_capacity                                = var.min_capacity
  max_capacity                                = var.max_capacity
  task_cpu                                    = var.task_cpu
  task_memory                                 = var.task_memory
  cpu_target_value                            = var.cpu_target_value
  memory_target_value                         = var.memory_target_value
  requests_target_value                       = var.requests_target_value
  scale_in_cooldown                           = var.scale_in_cooldown
  scale_out_cooldown                          = var.scale_out_cooldown
  app_host_header                             = var.app_host_header
  upstream_url                                = var.upstream_url
  enable_managed_observability                = var.enable_managed_observability
  observability_prometheus_image              = var.observability_prometheus_image
  observability_kong_job_name                 = var.observability_kong_job_name
  observability_scrape_interval               = var.observability_scrape_interval
  grafana_admin_user_ids                      = var.grafana_admin_user_ids
  grafana_editor_user_ids                     = var.grafana_editor_user_ids
  grafana_viewer_user_ids                     = var.grafana_viewer_user_ids
  grafana_admin_group_ids                     = var.grafana_admin_group_ids
  grafana_editor_group_ids                    = var.grafana_editor_group_ids
  grafana_viewer_group_ids                    = var.grafana_viewer_group_ids
  enable_grafana_dashboard_bootstrap          = var.enable_grafana_dashboard_bootstrap
  grafana_dashboard_service_account_token_ttl = var.grafana_dashboard_service_account_token_ttl
  grafana_prometheus_datasource_name          = var.grafana_prometheus_datasource_name
  tags                                        = var.tags
}
