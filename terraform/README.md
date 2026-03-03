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
- `aws`: Terraform creates a VPC, public subnets, an Application Load Balancer, an ECS/Fargate service for Kong, and target-tracking autoscaling based on CPU, memory, and proxy request load.
- `azure`: Terraform creates a resource group, network, and a single Ubuntu VM, then bootstraps Docker and runs Kong with Docker Compose.

This is intentionally lightweight for the assessment. Local uses a Terraform-to-Ansible handoff, AWS uses ECS/Fargate, and Azure stays on a single VM to keep the packaging understandable across targets.

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
- The AWS target exposes ports `8000`, `8001`, and `8002` through the ALB security group.
- The Azure target exposes ports `22`, `8000`, `8001`, and `8002` to the configured `admin_cidr`.
- The Terraform CLI is available locally; AWS configuration formatting and validation have been run, but a real `plan` still depends on valid cloud credentials and workspace variables.
