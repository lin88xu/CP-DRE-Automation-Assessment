terraform {
  required_providers {
    docker = {
      source = "kreuzwerker/docker"
    }
    local = {
      source = "hashicorp/local"
    }
  }
}

resource "local_file" "kong_config" {
  filename = abspath("${path.root}/docker-kong.generated.yml")
  content = templatefile("${path.module}/../../templates/docker-kong.yml.tftpl", {
    app_host_header = var.app_host_header
    upstream_url    = var.upstream_url
  })
}

resource "docker_network" "kong" {
  name = "${var.name_prefix}-network"
}

resource "docker_volume" "kong_db_data" {
  name = "${var.name_prefix}-db-data"
}

resource "docker_volume" "kong_data" {
  name = "${var.name_prefix}-data"
}

resource "docker_image" "postgres" {
  name = var.postgres_image
}

resource "docker_image" "kong" {
  name = var.kong_image
}

resource "docker_container" "kong_db" {
  name  = "${var.name_prefix}-db"
  image = docker_image.postgres.image_id
  env = [
    "POSTGRES_DB=kong",
    "POSTGRES_USER=kong",
    "POSTGRES_PASSWORD=kong",
  ]
  must_run = true
  restart  = "unless-stopped"

  ports {
    internal = 5432
    external = var.db_port
  }

  volumes {
    volume_name    = docker_volume.kong_db_data.name
    container_path = "/var/lib/postgresql/data"
  }

  networks_advanced {
    name = docker_network.kong.name
  }
}

resource "docker_container" "kong" {
  name  = var.name_prefix
  image = docker_image.kong.image_id
  env = [
    "KONG_DATABASE=off",
    "KONG_PROXY_ACCESS_LOG=/dev/stdout",
    "KONG_PROXY_ERROR_LOG=/dev/stderr",
    "KONG_PROXY_LISTEN=0.0.0.0:8000",
    "KONG_ADMIN_ACCESS_LOG=/dev/stdout",
    "KONG_ADMIN_ERROR_LOG=/dev/stderr",
    "KONG_ADMIN_LISTEN=0.0.0.0:8001",
    "KONG_ADMIN_GUI_URL=http://localhost:${var.manager_port}",
    "KONG_ADMIN_GUI_LISTEN=0.0.0.0:8002",
    "KONG_ADMIN_GUI_AUTH=basic-auth",
    "KONG_ADMIN_GUI_AUTH_CONF={\"secret\":\"kong-secret\"}",
    "KONG_ADMIN_GUI_SESSION_CONF={\"secret\":\"kong-session-secret\"}",
    "KONG_ENFORCE_RBAC=off",
    "KONG_LOG_LEVEL=info",
    "KONG_PREFIX=/usr/local/kong",
    "KONG_DECLARATIVE_CONFIG=/etc/kong/docker-kong.yml",
    "KONG_DECLARATIVE_CONFIG_ENCODED=false",
  ]
  must_run = true
  restart  = "unless-stopped"
  command  = ["kong", "docker-start"]

  ports {
    internal = 8000
    external = var.proxy_port
  }

  ports {
    internal = 8001
    external = var.admin_port
  }

  ports {
    internal = 8002
    external = var.manager_port
  }

  volumes {
    volume_name    = docker_volume.kong_data.name
    container_path = "/usr/local/kong"
  }

  volumes {
    host_path      = local_file.kong_config.filename
    container_path = "/etc/kong/docker-kong.yml"
    read_only      = true
  }

  networks_advanced {
    name = docker_network.kong.name
  }

  depends_on = [
    docker_container.kong_db,
    local_file.kong_config,
  ]
}
