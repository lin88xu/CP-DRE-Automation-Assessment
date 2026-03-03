# CP DRE Automation Assessment

This repository packages Kong Gateway as the application under assessment and wraps it with infrastructure automation, configuration management, CI/CD, and observability.

The same deployment model is intended to work across:

- Local Docker
- AWS
- Azure

## Architecture Overview

The solution is organized as a layered delivery model:

1. Terraform provisions the target environment.
2. Ansible configures the target host and deploys the application and observability stack.
3. Kong runs as the API gateway and management plane.
4. Prometheus scrapes Kong metrics.
5. Grafana visualizes service health and request behavior.
6. GitHub Actions validates Terraform, lints Ansible, and smoke-tests the observability path.

High-level flow:

```text
Git Push / Pull Request
        |
        v
GitHub Actions
  - Terraform validate
  - Ansible lint
  - Observability smoke test
        |
        v
Terraform
  - local host handoff
  - AWS ECS/Fargate
  - Azure single-host VM
        |
        v
Deployment Layer
  - AWS: ECS task definition + ALB
  - Local: Terraform handoff -> Ansible + Docker Compose
  - Azure: Ansible + Docker Compose
        |
        v
Kong Gateway
  - Proxy: 8000
  - Admin API: 8001
  - Manager UI: 8002
        |
        v
Prometheus -> Grafana
```

## Repository Layout

```text
.
├── README.md
├── .github/workflows/
│   ├── ansible-ci.yml
│   ├── local-deployment-e2e.yml
│   ├── observability-smoke.yml
│   └── terraform-ci.yml
├── terraform/
│   ├── environments/
│   │   ├── aws/
│   │   ├── azure/
│   │   └── local/
│   ├── modules/
│   └── templates/
├── anisible/
│   ├── inventories/
│   ├── playbooks/
│   └── roles/
├── deployment/
│   └── kong/
│       ├── docker-compose.yml
│       └── docker-kong.yml
├── promethusGrafana/
│   ├── prometheus/
│   └── grafana/
└── kong/
    ├── Makefile.docker
    └── kong-init.sh
```

Note: the repository uses the existing directory names `anisible/` and `promethusGrafana/`. The `kong/` directory is a git submodule for Kong source, while the local smoke-test compose files live under `deployment/kong/`.

## Deliverables Mapping

This repository contains the required deliverables from the assessment brief:

- IaC code:
  [terraform/](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/terraform)
- CI/CD pipeline configuration:
  [.github/workflows/terraform-ci.yml](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/.github/workflows/terraform-ci.yml),
  [.github/workflows/ansible-ci.yml](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/.github/workflows/ansible-ci.yml),
  [.github/workflows/local-deployment-e2e.yml](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/.github/workflows/local-deployment-e2e.yml),
  [.github/workflows/observability-smoke.yml](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/.github/workflows/observability-smoke.yml)
- Application and automation code:
  [deployment/kong/](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/deployment/kong),
  [kong/](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/kong),
  [anisible/](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/anisible),
  [promethusGrafana/](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/promethusGrafana)

## Infrastructure As Code

Terraform supports three targets:

- `terraform/environments/local`: prepares the local host handoff for Ansible and validates Docker availability
- `terraform/environments/aws`: provisions an AWS ECS/Fargate environment with an Application Load Balancer and ECS service autoscaling for Kong
- `terraform/environments/azure`: provisions a single-host Azure environment and boots Kong with Docker Compose

### AWS Architecture

The AWS target uses a container-native deployment model:

- A dedicated VPC with two public subnets across two availability zones
- An internet-facing Application Load Balancer exposing Kong proxy, Admin API, and Manager ports
- An ECS cluster running Kong on Fargate in DB-less mode
- CloudWatch Logs for container log collection
- ECS service autoscaling driven by CPU utilization, memory utilization, and ALB request count on the proxy target group

Traffic flow:

`Client -> ALB -> ECS/Fargate Kong task -> upstream service`

Shared templates keep the Kong deployment model consistent across all targets:

- [terraform/templates/docker-compose.yml.tftpl](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/terraform/templates/docker-compose.yml.tftpl)
- [terraform/templates/docker-kong.yml.tftpl](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/terraform/templates/docker-kong.yml.tftpl)

Design intent:

- Separate infrastructure from application configuration
- Recreate environments from scratch
- Reuse the same Kong packaging across local, AWS, and Azure

## Configuration Management

Ansible provides the configuration-management layer:

- Installs or validates Docker on the target host
- Renders Kong Compose and declarative config
- Renders Prometheus and Grafana config
- Starts both stacks with Docker Compose

Scope note:

- Ansible is the deployment layer for the local and Azure host-based paths.
- The local path uses Terraform to generate the Ansible inventory and variables handoff before Ansible deploys Kong and observability.
- The AWS target is container-native and packages Kong directly into ECS/Fargate with Terraform.

Key files:

- [anisible/playbooks/site.yml](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/anisible/playbooks/site.yml)
- [anisible/roles/kong/tasks/main.yml](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/anisible/roles/kong/tasks/main.yml)
- [anisible/roles/observability/tasks/main.yml](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/anisible/roles/observability/tasks/main.yml)
- [anisible/playbooks/group_vars/all.yml](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/anisible/playbooks/group_vars/all.yml)

## CI/CD And GitOps Flow

The GitHub Actions workflows implement the validation side of the GitOps path:

- Terraform validation:
  [.github/workflows/terraform-ci.yml](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/.github/workflows/terraform-ci.yml)
- Ansible lint and syntax check:
  [.github/workflows/ansible-ci.yml](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/.github/workflows/ansible-ci.yml)
- Local host-based deployment validation:
  [.github/workflows/local-deployment-e2e.yml](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/.github/workflows/local-deployment-e2e.yml)
- Kong and observability smoke test:
  [.github/workflows/observability-smoke.yml](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/.github/workflows/observability-smoke.yml)

Current pipeline stages demonstrated:

- Validate Terraform formatting and configuration
- Validate Ansible playbooks and roles
- Run Terraform `init`, `validate`, `plan`, and apply the local handoff layer
- Run the local Ansible deployment layer on `localhost` using Terraform-generated inventory and variables
- Verify Kong serves proxy and Admin traffic after deployment
- Boot Kong locally in CI
- Boot Prometheus and Grafana locally in CI
- Verify Grafana health
- Verify Prometheus can scrape Kong metrics
- Upload logs and summaries as workflow artifacts

Safe change practices included:

- Validation before deployment
- Independent workflow checks for branch protection
- Smoke test of the observability chain, not just syntax
- Artifacts and summaries for failed runs

## Observability Approach

The observability stack is under [promethusGrafana/](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/promethusGrafana).

Components:

- Prometheus for metrics collection
- Grafana for dashboarding
- Kong `prometheus` plugin enabled in declarative config

Important signals:

- Kong Admin API health
  Why it matters: operators need to know whether the management plane is reachable.
- Kong request metrics
  Why it matters: confirms live traffic and exposes service behavior.
- Kong latency metrics
  Why it matters: high latency is often the first sign of upstream or resource stress.
- Nginx connection metrics
  Why it matters: shows concurrency pressure and saturation indicators.
- Prometheus target health
  Why it matters: broken telemetry is itself an operational failure.
- Grafana health
  Why it matters: validates operator access to dashboards during incidents.

Relevant files:

- [promethusGrafana/prometheus/prometheus.yml](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/promethusGrafana/prometheus/prometheus.yml)
- [promethusGrafana/prometheus/rules/kong-alerts.yml](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/promethusGrafana/prometheus/rules/kong-alerts.yml)
- [promethusGrafana/grafana/dashboards/kong-overview.json](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/promethusGrafana/grafana/dashboards/kong-overview.json)

Operator investigation path:

1. Check Grafana dashboard health and request rate.
2. Check Prometheus target status for `kong-admin`.
3. Query Kong `/status` and `/metrics`.
4. Inspect container logs with Docker Compose.

## Resiliency Design

The design focuses on simple, observable failure handling rather than high-availability clustering.

Failure scenarios covered by the design:

1. Application failure:
   Kong container stops or fails health checks.
   Expected behavior: Docker restart policy and health checks expose the problem quickly.
   Recovery: restart the stack or re-run Ansible deployment.

2. Dependency failure:
   Upstream service is unreachable or slow.
   Expected behavior: Kong request errors and latency metrics increase.
   Recovery: inspect upstream, adjust routing, or roll back config.

3. Misconfiguration:
   Broken declarative config or invalid deployment change.
   Expected behavior: CI validation or smoke test should fail before rollout.
   Recovery: fix config in Git and redeploy, or revert to last known-good commit.

4. Telemetry failure:
   Prometheus cannot scrape Kong metrics.
   Expected behavior: Prometheus target becomes `down` and alerts fire.
   Recovery: inspect Kong Admin API, networking, or plugin configuration.

## Local Usage

Terraform handoff plus Ansible deployment:

```bash
cd terraform/environments/local
terraform init
terraform apply
```

```bash
cd <repo-root>/anisible

ANSIBLE_CONFIG=<repo-root>/anisible/ansible.cfg \
ansible-playbook \
  -K \
  -i ../terraform/environments/local/generated/hosts.yml \
  playbooks/site.yml \
  -e @../terraform/environments/local/generated/terraform-ansible-vars.yml
```

Replace `<repo-root>` with the directory where you cloned this repository. For example, that might be `/home/<user>/CP-DRE-Automation-Assessment` on Linux, or `/mnt/c/.../CP-DRE-Automation-Assessment` under WSL if the repo lives on a Windows-mounted drive.

If you run the repository from WSL under `/mnt/c/...`, Ansible treats that path as world-writable and ignores the local `ansible.cfg` unless `ANSIBLE_CONFIG` is set explicitly. If you prefer not to rely on `ansible.cfg`, use:

```bash
cd <repo-root>/anisible

ANSIBLE_ROLES_PATH=<repo-root>/anisible/roles \
ansible-playbook \
  -K \
  -i ../terraform/environments/local/generated/hosts.yml \
  playbooks/site.yml \
  -e @../terraform/environments/local/generated/terraform-ansible-vars.yml
```

For local runs, `-K` prompts for the sudo password used by `become`, which is required because the playbook installs packages and writes under `/opt`.

To stop the Ansible-managed local deployment and remove its containers and volumes:

```bash
cd <repo-root>/anisible

ANSIBLE_CONFIG=<repo-root>/anisible/ansible.cfg \
ansible-playbook \
  -K \
  -i ../terraform/environments/local/generated/hosts.yml \
  playbooks/teardown.yml \
  -e @../terraform/environments/local/generated/terraform-ansible-vars.yml
```

Direct smoke-test runtime:

```bash
cd deployment/kong
docker compose up -d
```

```bash
cd promethusGrafana
docker compose up -d
```

Useful local endpoints:

- Kong Proxy:
  `http://localhost:8000`
- Kong Admin API:
  `http://localhost:8001`
- Kong Manager UI:
  `http://localhost:8002`
- Prometheus:
  `http://localhost:9090`
- Grafana:
  `http://localhost:3000`

## Validation Status

Validated locally in this workspace:

- Terraform installed locally and `local` and `azure` environments validated
- Ansible installed locally and linted successfully
- Kong local stack starts and exposes `/status` and `/metrics`
- Prometheus scrapes Kong metrics successfully
- Grafana health is healthy
- GitHub Actions workflows were added for Terraform, Ansible, and observability smoke tests

Known limitation from local validation:

- `terraform validate` for the AWS environment did not complete successfully on this machine because the AWS provider plugin stopped responding during local validation. The HCL initializes, but provider-side validation needs separate follow-up on this host.

## Tradeoffs And Assumptions

Tradeoffs:

- AWS uses ECS/Fargate to avoid host management while Azure remains single-host for now.
- Docker Compose is used as the runtime packaging format across environments for consistency and speed.
- Kong runs in DB-less mode for simplicity and reproducibility, rather than full database-backed dynamic configuration.
- Observability focuses on metrics and logs first, without a full tracing stack.

Assumptions:

- Local development runs on a machine with Docker available.
- AWS and Azure credentials are supplied externally when using cloud targets.
- The current repository names `anisible/` and `promethusGrafana/` are preserved.
- This repository is assessment-oriented and optimized for clarity and operational intent over production scale.

## Next Steps

Natural extensions if more time were available:

1. Resolve the local AWS provider validation failure and add provider-level plan tests.
2. Add deployment workflows beyond validation-only CI.
3. Add rollback documentation and a concrete recovery runbook.
4. Add backup and restore procedures for persistent data.
5. Harden secrets handling and reduce default open access in cloud examples.
