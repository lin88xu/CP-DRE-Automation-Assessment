data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_partition" "current" {}

data "aws_region" "current" {}

data "aws_iam_policy_document" "ecs_task_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "grafana_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["grafana.amazonaws.com"]
    }
  }
}

locals {
  selected_azs = var.availability_zone != "" ? concat(
    [var.availability_zone],
    slice([for az in data.aws_availability_zones.available.names : az if az != var.availability_zone], 0, 1)
  ) : slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnet_cidrs = [var.subnet_cidr, var.secondary_subnet_cidr]
  docker_kong = templatefile("${path.module}/../../templates/docker-kong.yml.tftpl", {
    app_host_header = var.app_host_header
    upstream_url    = var.upstream_url
  })
  kong_container_name    = "${var.name_prefix}-kong"
  kong_config_string     = local.docker_kong
  kong_config_path       = "/tmp/docker-kong.yml"
  ecs_resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.this.name}"
  proxy_resource_label   = "${aws_lb.this.arn_suffix}/${aws_lb_target_group.proxy.arn_suffix}"
  amp_workspace_alias    = "${var.name_prefix}-amp"
  grafana_workspace_name = "${var.name_prefix}-grafana"
  amp_alert_rules = templatefile("${path.module}/../../templates/amp-kong-alerts.yml.tftpl", {
    observability_kong_job_name = var.observability_kong_job_name
  })
  amp_recording_rules = templatefile("${path.module}/../../templates/amp-kong-recording-rules.yml.tftpl", {
    observability_kong_job_name = var.observability_kong_job_name
  })
  amp_remote_write_url             = var.enable_managed_observability ? "${aws_prometheus_workspace.this[0].prometheus_endpoint}api/v1/remote_write" : null
  grafana_bootstrap_enabled        = var.enable_managed_observability && var.enable_grafana_dashboard_bootstrap
  grafana_bootstrap_dashboard_path = "${path.module}/../../templates/kong-official.json"
  grafana_bootstrap_script_path    = "${path.module}/../../scripts/import_amg_dashboard.py"
  common_tags = merge(var.tags, {
    ManagedBy = "Terraform"
  })
  grafana_role_assignments = var.enable_managed_observability ? {
    admin = {
      role      = "ADMIN"
      user_ids  = toset(var.grafana_admin_user_ids)
      group_ids = toset(var.grafana_admin_group_ids)
    }
    editor = {
      role      = "EDITOR"
      user_ids  = toset(var.grafana_editor_user_ids)
      group_ids = toset(var.grafana_editor_group_ids)
    }
    viewer = {
      role      = "VIEWER"
      user_ids  = toset(var.grafana_viewer_user_ids)
      group_ids = toset(var.grafana_viewer_group_ids)
    }
  } : {}
  grafana_role_assignments_enabled = {
    for key, value in local.grafana_role_assignments : key => value
    if length(value.user_ids) > 0 || length(value.group_ids) > 0
  }
  grafana_user_role_overlap = setunion(
    setintersection(toset(var.grafana_admin_user_ids), toset(var.grafana_editor_user_ids)),
    setintersection(toset(var.grafana_admin_user_ids), toset(var.grafana_viewer_user_ids)),
    setintersection(toset(var.grafana_editor_user_ids), toset(var.grafana_viewer_user_ids))
  )
  grafana_group_role_overlap = setunion(
    setintersection(toset(var.grafana_admin_group_ids), toset(var.grafana_editor_group_ids)),
    setintersection(toset(var.grafana_admin_group_ids), toset(var.grafana_viewer_group_ids)),
    setintersection(toset(var.grafana_editor_group_ids), toset(var.grafana_viewer_group_ids))
  )
  kong_container_definition = {
    name       = local.kong_container_name
    image      = var.kong_image
    essential  = true
    entryPoint = ["/bin/sh", "-ec"]
    command = [join("\n", [
      "cat <<'EOF' >${local.kong_config_path}",
      local.kong_config_string,
      "EOF",
      "exec /docker-entrypoint.sh kong docker-start"
    ])]
    portMappings = [
      {
        containerPort = 8000
        hostPort      = 8000
        protocol      = "tcp"
      },
      {
        containerPort = 8001
        hostPort      = 8001
        protocol      = "tcp"
      },
      {
        containerPort = 8002
        hostPort      = 8002
        protocol      = "tcp"
      }
    ]
    environment = [
      { name = "KONG_DATABASE", value = "off" },
      { name = "KONG_PROXY_ACCESS_LOG", value = "/dev/stdout" },
      { name = "KONG_PROXY_ERROR_LOG", value = "/dev/stderr" },
      { name = "KONG_PROXY_LISTEN", value = "0.0.0.0:8000" },
      { name = "KONG_ADMIN_ACCESS_LOG", value = "/dev/stdout" },
      { name = "KONG_ADMIN_ERROR_LOG", value = "/dev/stderr" },
      { name = "KONG_ADMIN_LISTEN", value = "0.0.0.0:8001" },
      { name = "KONG_ADMIN_GUI_URL", value = "http://${aws_lb.this.dns_name}:${var.manager_port}" },
      { name = "KONG_ADMIN_GUI_LISTEN", value = "0.0.0.0:8002" },
      { name = "KONG_ADMIN_GUI_AUTH", value = "basic-auth" },
      { name = "KONG_ADMIN_GUI_AUTH_CONF", value = "{\"secret\":\"kong-secret\"}" },
      { name = "KONG_ADMIN_GUI_SESSION_CONF", value = "{\"secret\":\"kong-session-secret\"}" },
      { name = "KONG_ENFORCE_RBAC", value = "off" },
      { name = "KONG_LOG_LEVEL", value = "info" },
      { name = "KONG_PREFIX", value = "/usr/local/kong" },
      { name = "KONG_DECLARATIVE_CONFIG", value = local.kong_config_path },
      { name = "KONG_DECLARATIVE_CONFIG_ENCODED", value = "false" }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.kong.name
        awslogs-region        = data.aws_region.current.name
        awslogs-stream-prefix = "kong"
      }
    }
  }
  amp_collector_config = var.enable_managed_observability ? yamlencode({
    global = {
      scrape_interval     = var.observability_scrape_interval
      evaluation_interval = var.observability_scrape_interval
    }
    scrape_configs = [
      {
        job_name     = var.observability_kong_job_name
        metrics_path = "/metrics"
        static_configs = [
          {
            targets = ["127.0.0.1:8001"]
            labels = {
              environment   = "managed"
              scrape_target = "kong"
            }
          }
        ]
      }
    ]
    remote_write = [
      {
        url = local.amp_remote_write_url
        sigv4 = {
          region = data.aws_region.current.name
        }
      }
    ]
  }) : null
  amp_collector_bootstrap = var.enable_managed_observability ? join("\n", [
    "cat <<'EOF' >/tmp/prometheus.yaml",
    local.amp_collector_config,
    "EOF",
    "exec /bin/prometheus \\",
    "  --config.file=/tmp/prometheus.yaml \\",
    "  --storage.agent.path=/tmp/prometheus-agent \\",
    "  --enable-feature=agent"
  ]) : null
  amp_collector_container_definition = var.enable_managed_observability ? {
    name      = "${var.name_prefix}-amp-collector"
    image     = var.observability_prometheus_image
    essential = true
    dependsOn = [
      {
        containerName = local.kong_container_name
        condition     = "START"
      }
    ]
    entryPoint = ["/bin/sh", "-ec"]
    command    = [local.amp_collector_bootstrap]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.kong.name
        awslogs-region        = data.aws_region.current.name
        awslogs-stream-prefix = "amp-collector"
      }
    }
  } : null
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-vpc"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-igw"
  })
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = local.selected_azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-public-subnet-${count.index + 1}"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "Access for Kong ALB"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "Kong Proxy"
    from_port   = var.proxy_port
    to_port     = var.proxy_port
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "Kong Admin API"
    from_port   = var.admin_port
    to_port     = var.admin_port
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "Kong Manager UI"
    from_port   = var.manager_port
    to_port     = var.manager_port
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-alb-sg"
  })
}

resource "aws_security_group" "task" {
  name        = "${var.name_prefix}-task-sg"
  description = "Access for Kong ECS tasks"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "ALB to Proxy"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "ALB to Admin API"
    from_port       = 8001
    to_port         = 8001
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "ALB to Manager UI"
    from_port       = 8002
    to_port         = 8002
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-task-sg"
  })
}

resource "aws_lb" "this" {
  name               = substr("${var.name_prefix}-alb", 0, 32)
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-alb"
  })
}

resource "aws_lb_target_group" "proxy" {
  name        = substr("${var.name_prefix}-proxy", 0, 32)
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.this.id
  target_type = "ip"

  health_check {
    path                = "/"
    matcher             = "200-499"
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-proxy"
  })
}

resource "aws_lb_target_group" "admin" {
  name        = substr("${var.name_prefix}-admin", 0, 32)
  port        = 8001
  protocol    = "HTTP"
  vpc_id      = aws_vpc.this.id
  target_type = "ip"

  health_check {
    path                = "/status"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-admin"
  })
}

resource "aws_lb_target_group" "manager" {
  name        = substr("${var.name_prefix}-manager", 0, 32)
  port        = 8002
  protocol    = "HTTP"
  vpc_id      = aws_vpc.this.id
  target_type = "ip"

  health_check {
    path                = "/"
    matcher             = "200-399"
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-manager"
  })
}

resource "aws_lb_listener" "proxy" {
  load_balancer_arn = aws_lb.this.arn
  port              = var.proxy_port
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.proxy.arn
  }
}

resource "aws_lb_listener" "admin" {
  load_balancer_arn = aws_lb.this.arn
  port              = var.admin_port
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.admin.arn
  }
}

resource "aws_lb_listener" "manager" {
  load_balancer_arn = aws_lb.this.arn
  port              = var.manager_port
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.manager.arn
  }
}

resource "aws_cloudwatch_log_group" "kong" {
  name              = "/ecs/${var.name_prefix}"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-logs"
  })
}

resource "aws_prometheus_workspace" "this" {
  count = var.enable_managed_observability ? 1 : 0

  alias = local.amp_workspace_alias

  tags = merge(local.common_tags, {
    Name = local.amp_workspace_alias
  })
}

resource "aws_prometheus_rule_group_namespace" "alerts" {
  count = var.enable_managed_observability ? 1 : 0

  workspace_id = aws_prometheus_workspace.this[0].id
  name         = "kong-alerts"
  data         = local.amp_alert_rules

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-kong-alerts"
  })
}

resource "aws_prometheus_rule_group_namespace" "recording" {
  count = var.enable_managed_observability ? 1 : 0

  workspace_id = aws_prometheus_workspace.this[0].id
  name         = "kong-recording-rules"
  data         = local.amp_recording_rules

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-kong-recording-rules"
  })
}

resource "aws_iam_role" "execution" {
  name               = "${var.name_prefix}-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-execution-role"
  })
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task" {
  count = var.enable_managed_observability ? 1 : 0

  name               = "${var.name_prefix}-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-task-role"
  })
}

resource "aws_iam_role_policy_attachment" "task_amp_remote_write" {
  count = var.enable_managed_observability ? 1 : 0

  role       = aws_iam_role.task[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonPrometheusRemoteWriteAccess"
}

resource "aws_iam_role" "grafana" {
  count = var.enable_managed_observability ? 1 : 0

  name               = "${var.name_prefix}-grafana-role"
  assume_role_policy = data.aws_iam_policy_document.grafana_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-grafana-role"
  })
}

resource "aws_iam_role_policy_attachment" "grafana_amp_query" {
  count = var.enable_managed_observability ? 1 : 0

  role       = aws_iam_role.grafana[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonPrometheusQueryAccess"
}

resource "aws_grafana_workspace" "this" {
  count = var.enable_managed_observability ? 1 : 0

  name                     = local.grafana_workspace_name
  description              = "Managed Grafana workspace for Kong observability."
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type          = "CUSTOMER_MANAGED"
  role_arn                 = aws_iam_role.grafana[0].arn
  data_sources             = ["PROMETHEUS"]

  tags = merge(local.common_tags, {
    Name = local.grafana_workspace_name
  })

  depends_on = [aws_iam_role_policy_attachment.grafana_amp_query]

  lifecycle {
    precondition {
      condition     = length(local.grafana_user_role_overlap) == 0
      error_message = "Each Grafana user ID can only be assigned to one AMG role. Remove duplicates across admin/editor/viewer user lists."
    }

    precondition {
      condition     = length(local.grafana_group_role_overlap) == 0
      error_message = "Each Grafana group ID can only be assigned to one AMG role. Remove duplicates across admin/editor/viewer group lists."
    }
  }
}

resource "aws_grafana_role_association" "roles" {
  for_each = local.grafana_role_assignments_enabled

  workspace_id = aws_grafana_workspace.this[0].id
  role         = each.value.role
  user_ids     = each.value.user_ids
  group_ids    = each.value.group_ids
}

resource "aws_grafana_workspace_service_account" "dashboard_bootstrap" {
  count = local.grafana_bootstrap_enabled ? 1 : 0

  workspace_id = aws_grafana_workspace.this[0].id
  name         = "${var.name_prefix}-dashboard-bootstrap"
  grafana_role = "ADMIN"
}

resource "aws_grafana_workspace_service_account_token" "dashboard_bootstrap" {
  count = local.grafana_bootstrap_enabled ? 1 : 0

  workspace_id       = aws_grafana_workspace.this[0].id
  service_account_id = aws_grafana_workspace_service_account.dashboard_bootstrap[0].service_account_id
  name               = "${var.name_prefix}-dashboard-bootstrap-token"
  seconds_to_live    = var.grafana_dashboard_service_account_token_ttl
}

resource "terraform_data" "grafana_dashboard_bootstrap" {
  count = local.grafana_bootstrap_enabled ? 1 : 0

  triggers_replace = [
    filesha256(local.grafana_bootstrap_dashboard_path),
    aws_grafana_workspace.this[0].endpoint,
    aws_grafana_workspace_service_account_token.dashboard_bootstrap[0].service_account_token_id,
    aws_prometheus_workspace.this[0].prometheus_endpoint,
    var.grafana_prometheus_datasource_name,
    data.aws_region.current.name,
  ]

  provisioner "local-exec" {
    command = "python3 ${local.grafana_bootstrap_script_path}"

    environment = {
      AMG_URL         = aws_grafana_workspace.this[0].endpoint
      AMG_TOKEN       = aws_grafana_workspace_service_account_token.dashboard_bootstrap[0].key
      AMP_QUERY_URL   = aws_prometheus_workspace.this[0].prometheus_endpoint
      AWS_REGION      = data.aws_region.current.name
      DASHBOARD_JSON  = local.grafana_bootstrap_dashboard_path
      DATASOURCE_NAME = var.grafana_prometheus_datasource_name
    }
  }

  depends_on = [
    aws_grafana_role_association.roles,
    aws_grafana_workspace_service_account_token.dashboard_bootstrap
  ]
}

resource "aws_ecs_cluster" "this" {
  name = "${var.name_prefix}-cluster"

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-cluster"
  })
}

resource "aws_ecs_task_definition" "this" {
  family                   = "${var.name_prefix}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.task_cpu)
  memory                   = tostring(var.task_memory)
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = var.enable_managed_observability ? aws_iam_role.task[0].arn : null

  container_definitions = jsonencode(concat(
    [local.kong_container_definition],
    var.enable_managed_observability ? [local.amp_collector_container_definition] : []
  ))

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-task"
  })
}

resource "aws_ecs_service" "this" {
  name                              = "${var.name_prefix}-service"
  cluster                           = aws_ecs_cluster.this.id
  task_definition                   = aws_ecs_task_definition.this.arn
  desired_count                     = var.desired_count
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 60

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.task.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.proxy.arn
    container_name   = local.kong_container_name
    container_port   = 8000
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.admin.arn
    container_name   = local.kong_container_name
    container_port   = 8001
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.manager.arn
    container_name   = local.kong_container_name
    container_port   = 8002
  }

  depends_on = [
    aws_lb_listener.proxy,
    aws_lb_listener.admin,
    aws_lb_listener.manager,
    aws_iam_role_policy_attachment.execution,
    aws_prometheus_rule_group_namespace.alerts,
    aws_prometheus_rule_group_namespace.recording
  ]

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-service"
  })
}

resource "aws_appautoscaling_target" "ecs_service" {
  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id        = local.ecs_resource_id
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu_target_tracking" {
  name               = "${var.name_prefix}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_service.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_service.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_service.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value       = var.cpu_target_value
    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown
  }
}

resource "aws_appautoscaling_policy" "memory_target_tracking" {
  name               = "${var.name_prefix}-memory-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_service.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_service.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_service.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }

    target_value       = var.memory_target_value
    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown
  }
}

resource "aws_appautoscaling_policy" "requests_target_tracking" {
  name               = "${var.name_prefix}-requests-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_service.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_service.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_service.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = local.proxy_resource_label
    }

    target_value       = var.requests_target_value
    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown
  }
}
