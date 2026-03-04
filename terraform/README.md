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
- `aws`: Terraform creates a VPC, public subnets, an Application Load Balancer, an ECS/Fargate service for Kong, Amazon Managed Service for Prometheus, Amazon Managed Grafana, and target-tracking autoscaling based on CPU, memory, and proxy request load.
- `azure`: Terraform creates a resource group, network, and a single Ubuntu VM, then bootstraps Docker and runs Kong with Docker Compose.

This is intentionally lightweight for the assessment. Local uses a Terraform-to-Ansible handoff, AWS uses ECS/Fargate with managed observability, and Azure stays on a single VM to keep the packaging understandable across targets.

## Disaster Recovery

For a major outage, use the repo-native rebuild wrapper:

```bash
./terraform/disaster-recovery.sh local rebuild
./terraform/disaster-recovery.sh aws rebuild -- -var-file=terraform.tfvars
./terraform/disaster-recovery.sh azure rebuild -- -var-file=terraform.tfvars
```

What it does:

- `local`: runs the local runtime teardown and redeploy flow, then verifies the rebuilt stack by default
- `aws`: runs `terraform init`, `terraform destroy`, and `terraform apply` for `terraform/environments/aws`
- `azure`: runs `terraform init`, `terraform destroy`, and `terraform apply` for `terraform/environments/azure`

For dry-run recovery planning:

```bash
./terraform/disaster-recovery.sh aws plan -- -var-file=terraform.tfvars
./terraform/disaster-recovery.sh azure plan -- -var-file=terraform.tfvars
```

Logs are written under `terraform/recovery-artifacts/`.

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
# fill in aws_region, CIDR values, and any task sizing overrides
terraform init
terraform apply
```

## Deployment Model

- `local`: Terraform validates the local Docker host and generates the inventory and variables that Ansible uses for deployment.
- `aws`: Terraform creates a VPC, public subnets, an Application Load Balancer, an ECS/Fargate service for Kong, Amazon Managed Service for Prometheus, Amazon Managed Grafana, and target-tracking autoscaling based on CPU, memory, and proxy request load.
- `azure`: Terraform creates a resource group, network, and a single Ubuntu VM, then bootstraps Docker and runs Kong with Docker Compose.

This is intentionally lightweight for the assessment. Local uses a Terraform-to-Ansible handoff, AWS uses ECS/Fargate with managed observability, and Azure stays on a single VM to keep the packaging understandable across targets.

## AWS Verification

Use the outputs first:

```bash
cd terraform/environments/aws
terraform output proxy_url
terraform output admin_url
terraform output amp_prometheus_endpoint
terraform output grafana_workspace_url
```

1. Confirm Kong is up:

```bash
curl -sS "$(terraform output -raw admin_url)/status"
```

2. Send sample traffic through Kong. If you kept the default route settings, use the default host header:

```bash
for i in $(seq 1 20); do
  curl -sS -H "Host: example.com" "$(terraform output -raw proxy_url)/" >/dev/null
done
```

The AWS target provisions an AMP workspace plus an AMG workspace. Because the pinned AWS provider only exposes the managed scraper for EKS sources, the ECS task includes a small Prometheus sidecar that scrapes Kong locally and remote-writes to AMP.

Azure:

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

If metrics do not appear, check the ECS task logs in CloudWatch under `/ecs/<name_prefix>` and look for the `amp-collector` and `kong` log streams.

- Docker must already be available for the `local` target.
- AWS credentials and Azure credentials must be configured in the shell or standard provider locations.
- The AWS target exposes ports `8000`, `8001`, and `8002` through the ALB security group.
- The AWS target assumes IAM Identity Center / AWS SSO is available for logging into the Amazon Managed Grafana workspace.
- The Azure target exposes ports `22`, `8000`, `8001`, and `8002` to the configured `admin_cidr`.
- The Terraform CLI is available locally; AWS configuration formatting and validation have been run, but a real `plan` still depends on valid cloud credentials and workspace variables.
