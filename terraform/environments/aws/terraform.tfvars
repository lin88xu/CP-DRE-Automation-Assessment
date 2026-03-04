aws_region                    = "ap-southeast-1"
admin_cidr                    = "0.0.0.0/0"
subnet_cidr                   = "10.20.1.0/24"
secondary_subnet_cidr         = "10.20.2.0/24"
publish_admin_api             = true
publish_manager_ui            = false
desired_count                 = 1
min_capacity                  = 1
max_capacity                  = 1
task_cpu                      = 1024
task_memory                   = 2048
cpu_target_value              = 60
memory_target_value           = 70
requests_target_value         = 1000
scale_in_cooldown             = 120
scale_out_cooldown            = 60
enable_managed_observability  = true
observability_kong_job_name   = "kong-admin"
observability_scrape_interval = "10s"
enable_efs_backups            = true
efs_backup_schedule           = "cron(0 5 ? * * *)"
efs_backup_delete_after_days  = 35
grafana_admin_user_ids = [
  "c4780468-f0f1-70e2-97fc-61cabad4184b"
]
grafana_editor_user_ids                     = []
grafana_viewer_user_ids                     = []
grafana_admin_group_ids                     = []
grafana_editor_group_ids                    = []
grafana_viewer_group_ids                    = []
enable_grafana_dashboard_bootstrap          = true
grafana_dashboard_service_account_token_ttl = 14400
grafana_prometheus_datasource_name          = "Amazon Managed Service for Prometheus"

# Kong runs on ECS/Fargate behind an ALB in the AWS target, with PostgreSQL
# persisted on EFS and protected by AWS Backup.
# Managed observability adds an AMP workspace, an AMG workspace, and a Prometheus
# sidecar in the ECS task that scrapes Kong and remote-writes to AMP.
# Leave publish_admin_api and publish_manager_ui disabled unless you explicitly
# need direct public management access, and keep desired_count/min_capacity/
# max_capacity at 1 for this task-local PostgreSQL design.
upstream_url = "http://127.0.0.1:9"
