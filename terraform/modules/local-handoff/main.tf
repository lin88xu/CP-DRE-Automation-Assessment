locals {
  generated_dir = abspath("${path.root}/generated")

  inventory = {
    all = {
      children = {
        kong_hosts = {
          hosts = {
            localhost = {
              ansible_connection = "local"
              ansible_become     = true
              ansible_host       = "localhost"
            }
          }
        }
      }
    }
  }

  ansible_vars = {
    kong_install_root                    = var.kong_install_root
    kong_name_prefix                     = var.name_prefix
    kong_public_host                     = var.public_host
    kong_proxy_port                      = var.proxy_port
    kong_admin_port                      = var.admin_port
    kong_manager_port                    = var.manager_port
    kong_db_port                         = var.db_port
    kong_image                           = var.kong_image
    kong_postgres_image                  = var.postgres_image
    kong_app_host_header                 = var.app_host_header
    kong_upstream_url                    = var.upstream_url
    observability_install_root           = var.observability_install_root
    observability_prometheus_port        = var.observability_prometheus_port
    observability_grafana_port           = var.observability_grafana_port
    observability_prometheus_image       = var.observability_prometheus_image
    observability_grafana_image          = var.observability_grafana_image
    observability_grafana_admin_user     = var.observability_grafana_admin_user
    observability_grafana_admin_password = var.observability_grafana_admin_password
    observability_scrape_host            = var.observability_scrape_host
    observability_scrape_port            = var.admin_port
    observability_kong_job_name          = var.observability_kong_job_name
  }
}

resource "terraform_data" "docker_preflight" {
  provisioner "local-exec" {
    command = "docker info >/dev/null"
  }
}

resource "local_file" "ansible_inventory" {
  filename             = "${local.generated_dir}/hosts.yml"
  content              = yamlencode(local.inventory)
  directory_permission = "0755"
  file_permission      = "0644"

  depends_on = [
    terraform_data.docker_preflight,
  ]
}

resource "local_file" "ansible_vars" {
  filename             = "${local.generated_dir}/terraform-ansible-vars.yml"
  content              = yamlencode(local.ansible_vars)
  directory_permission = "0755"
  file_permission      = "0644"

  depends_on = [
    terraform_data.docker_preflight,
  ]
}
