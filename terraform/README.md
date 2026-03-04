# Terraform Targets

This directory provides Terraform entrypoints for deploying the Kong demo stack to:

- Local host handoff
- AWS
- Azure

The structure is split between reusable modules and target-specific environments:

```text
terraform/
├── environments/
│   ├── aws/
│   │   └── modules/aws-ecs-service/
│   ├── azure/
│   └── local/
├── modules/
│   ├── azure-single-host/
│   └── local-handoff/
└── templates/
    ├── cloud-init-kong.sh.tftpl
    ├── docker-compose.yml.tftpl
    └── docker-kong.yml.tftpl
```

## Deployment Model

- `local`: Terraform validates the local Docker host and generates the inventory and variables that Ansible uses for deployment.
- `aws`: Terraform creates a VPC, public subnets, an Application Load Balancer, an ECS/Fargate service for Kong, EFS-backed PostgreSQL persistence, AWS Secrets Manager secrets, AWS Backup protection for the database volume, Amazon Managed Service for Prometheus, and Amazon Managed Grafana.
- `azure`: Terraform creates a resource group, network, and a single Ubuntu VM, then bootstraps Docker and runs Kong with Docker Compose.

This is intentionally lightweight for the assessment. Local uses a Terraform-to-Ansible handoff, AWS uses ECS/Fargate with managed observability and task-local PostgreSQL persisted on EFS, and Azure stays on a single VM to keep the packaging understandable across targets.

## Usage

Local handoff:

```bash
cd terraform/environments/local
terraform init
terraform apply
```

Then deploy the stack with the generated handoff files:

```bash
cd anisible
ansible-playbook \
  -i ../terraform/environments/local/generated/hosts.yml \
  playbooks/site.yml \
  -e @../terraform/environments/local/generated/terraform-ansible-vars.yml
```

AWS:

```bash
cd terraform/environments/aws
cp terraform.tfvars.example terraform.tfvars
# fill in aws_region, CIDR values, and any required IAM Identity Center IDs
terraform init
terraform apply
```

After apply, Terraform prints the standard Kong URLs needed for operator access, including `proxy_url`, `admin_url` when enabled, `manager_url` when enabled, and `grafana_workspace_url`.

The AWS target provisions an AMP workspace plus an AMG workspace. Because the pinned AWS provider only exposes the managed scraper for EKS sources, the ECS task includes a small Prometheus sidecar that runs in agent mode, scrapes Kong's internal Status API locally, and remote-writes to AMP.
Kong runs in DB mode in this target. PostgreSQL is task-local, persisted on EFS, protected by AWS Backup, and its credentials plus Kong Manager secrets are injected from AWS Secrets Manager.
If you want Terraform to grant Amazon Managed Grafana access automatically, set the IAM Identity Center user IDs and group IDs in `terraform/environments/aws/terraform.tfvars`. The AWS target supports separate Admin, Editor, and Viewer assignments for both users and groups.
Terraform also bootstraps the AMG workspace by creating an AMP-backed Prometheus data source and importing the `Kong (official)` dashboard.
For security hygiene, public access to the Kong Admin API and Kong Manager is disabled by default; only the proxy listener is published unless you explicitly enable the management endpoints.

This DB-backed ECS design is intentionally constrained to a single task. Keep `desired_count`, `min_capacity`, and `max_capacity` at `1` unless you first move PostgreSQL to a dedicated multi-client database service such as Amazon RDS.

## AWS Verification

Use the outputs first:

```bash
cd terraform/environments/aws
terraform output proxy_url
terraform output admin_url
terraform output grafana_workspace_url
```

1. Confirm the public proxy is up:

```bash
curl -sS -H "Host: example.com" "$(terraform output -raw proxy_url)/" >/dev/null
```

2. If you explicitly enabled the public Admin API, confirm Kong status:

```bash
curl -sS "$(terraform output -raw admin_url)/status"
```

3. Send sample traffic through Kong. If you kept the default route settings, use the default host header:

```bash
for i in $(seq 1 20); do
  curl -sS -H "Host: example.com" "$(terraform output -raw proxy_url)/" >/dev/null
done
```

4. Wait 1 to 2 minutes for the ECS Prometheus sidecar to scrape Kong's internal Status API and remote-write into AMP.

5. Open the Grafana workspace URL:

```bash
terraform output -raw grafana_workspace_url
```

Sign in with AWS SSO / IAM Identity Center, then use Explore or a dashboard to run:

```text
up{job="kong-admin",scrape_target="kong"}
sum(rate(kong_http_requests_total[5m]))
```

Expected result:

- `up{job="kong-admin",scrape_target="kong"}` returns `1`
- `sum(rate(kong_http_requests_total[5m]))` is greater than `0` after test traffic

If metrics do not appear, check the ECS task logs in CloudWatch under `/ecs/<name_prefix>` and look for the `amp-collector` and `kong` log streams. The collector is expected to start Prometheus in agent mode with `--storage.agent.path`, not `--storage.tsdb.path`.

For rollback and EFS backup recovery procedures, see [docs/AWS_RECOVERY_RUNBOOK.md](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/docs/AWS_RECOVERY_RUNBOOK.md).

Azure:

```bash
cd terraform/environments/azure
cp terraform.tfvars.example terraform.tfvars
# fill in subscription_id, location, ssh_public_key_path, and any overrides
terraform init
terraform apply
```

## Local Outputs

After `terraform apply` in `terraform/environments/local`, Terraform writes:

- `generated/hosts.yml`: local Ansible inventory
- `generated/terraform-ansible-vars.yml`: local deployment variables

It also exposes `inventory_file`, `vars_file`, and `ansible_deploy_command` via `terraform output`.

## Assumptions

- Docker must already be available for the `local` target.
- AWS credentials and Azure credentials must be configured in the shell or standard provider locations.
- The AWS target always exposes the proxy port `8000`. The Admin API and Manager are unpublished by default and only become reachable if `publish_admin_api` and `publish_manager_ui` are enabled.
- The AWS DB-backed ECS path is intentionally single-task because PostgreSQL is task-local and persisted on EFS for recovery rather than clustering.
- The Azure target exposes ports `22`, `8000`, `8001`, and `8002` to the configured `admin_cidr`.
- The Terraform CLI is available locally; AWS configuration formatting and validation have been run, but a real `plan` still depends on valid cloud credentials and workspace variables.
