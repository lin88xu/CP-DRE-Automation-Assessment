# CP DRE Automation Assessment

This repository packages Kong Gateway as the application under assessment and wraps it with infrastructure automation, CI/CD, observability, and recovery controls.

This branch is written around the AWS deployment path. The repository still contains local and Azure artifacts, but the primary runtime described here is Kong on AWS ECS/Fargate.

## Prerequisites

Before working with the AWS deployment branch, make sure the operator environment has:

- `git`
- `terraform`
- `python3`
- AWS credentials available through the standard provider chain or HCP Terraform workspace variables
- access to the target AWS account and region

Useful preflight checks:

```bash
terraform version
python3 --version
aws sts get-caller-identity
```

## Architecture Overview

The AWS branch is organized as a layered delivery model:

1. GitHub Actions validates infrastructure and observability changes before deployment.
2. Terraform provisions the AWS network, ECS service, persistent storage, secrets, observability backends, and recovery controls.
3. ECS/Fargate runs PostgreSQL, Kong bootstrap, Kong runtime, and the Prometheus agent sidecar in one coordinated task.
4. Kong serves proxy traffic through the ALB and stores its runtime state in PostgreSQL on EFS.
5. The Prometheus sidecar scrapes Kong metrics and remote-writes them to AMP.
6. AMG queries AMP and presents dashboards for operators.
7. CloudWatch Logs, ECS rollback, and AWS Backup provide the operational recovery path.

High-level flow:

```text
Git Push / Pull Request
        |
        v
GitHub Actions
  - Terraform validate
  - Ansible lint
  - Observability smoke test
  - AWS terraform plan/apply deploy
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
│   ├── aws-deploy.yml
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
  [.github/workflows/aws-deploy.yml](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/.github/workflows/aws-deploy.yml),
  [.github/workflows/observability-smoke.yml](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/.github/workflows/observability-smoke.yml)
- Application and automation code:
  [deployment/kong/](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/deployment/kong),
  [kong/](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/kong),
  [anisible/](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/anisible),
  [promethusGrafana/](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/promethusGrafana)
- Recovery and operations documentation:
  [docs/AWS_RECOVERY_RUNBOOK.md](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/docs/AWS_RECOVERY_RUNBOOK.md)
- Verification assets:
  [tests/TP_REMOTE_STACK_VERIFICATION_V001.py](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/tests/TP_REMOTE_STACK_VERIFICATION_V001.py),
  [tests/TP_DASHBOARD_CONTENT_CORRECTNESS_V001.py](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/tests/TP_DASHBOARD_CONTENT_CORRECTNESS_V001.py),
  [tests/TP_APPLICATION_FAILURE_RECOVERY_V001.py](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/tests/TP_APPLICATION_FAILURE_RECOVERY_V001.py),
  [tests/TP_MISCONFIGURATION_RECOVERY_V001.py](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/tests/TP_MISCONFIGURATION_RECOVERY_V001.py)
  These verification assets are used against the remote AWS deployment shape by default.

## Assessment Compliance

This section maps the assessment brief directly to the repository files that implement each requirement.

- Infrastructure as Code:
  `terraform/environments/aws/main.tf`, `terraform/environments/aws/modules/aws-ecs-service/main.tf`, `terraform/environments/aws/variables.tf`
- Environment can be recreated from scratch:
  `terraform/disaster-recovery.sh`, `docs/AWS_RECOVERY_RUNBOOK.md`, `terraform/environments/aws/terraform.tfvars`
- Clear separation between infrastructure, application, and configuration:
  `terraform/`, `kong/`, `terraform/environments/aws/templates/docker-kong.yml.tftpl`
- Configuration management through Ansible or equivalent:
  `anisible/playbooks/site.yml`, `anisible/roles/kong/tasks/main.yml`, `anisible/roles/observability/tasks/main.yml`, plus AWS ECS bootstrap logic in `terraform/environments/aws/modules/aws-ecs-service/main.tf`
- CI/CD pipeline through GitHub Actions:
  `.github/workflows/terraform-ci.yml`, `.github/workflows/ansible-ci.yml`, `.github/workflows/observability-smoke.yml`, `.github/workflows/aws-deploy.yml`
- Validation, plan, and deployment stages:
  `.github/workflows/terraform-ci.yml`, `.github/workflows/aws-deploy.yml`
- Safe change practices:
  `.github/workflows/aws-deploy.yml`, `docs/AWS_RECOVERY_RUNBOOK.md`, ECS deployment settings in `terraform/environments/aws/modules/aws-ecs-service/main.tf`
- Observability with logs and metrics:
  `terraform/environments/aws/modules/aws-ecs-service/main.tf`, `terraform/environments/aws/templates/amp-kong-alerts.yml.tftpl`, `tests/TP_DASHBOARD_CONTENT_CORRECTNESS_V001.py`
- Explanation of important signals and operator investigation path:
  this README under `Observability Approach`, plus `docs/AWS_RECOVERY_RUNBOOK.md`
- Resiliency and recovery thinking:
  this README under `Resiliency Design`, `docs/AWS_RECOVERY_RUNBOOK.md`, `terraform/disaster-recovery.sh`
- At least two failure scenarios with recovery:
  `tests/TP_APPLICATION_FAILURE_RECOVERY_V001.py`, `tests/TP_MISCONFIGURATION_RECOVERY_V001.py`
- README coverage for architecture, observability, resiliency, tradeoffs, and assumptions:
  this README

## Infrastructure As Code

This branch is centered on the AWS target:

- `terraform/environments/aws`: provisions the AWS runtime, observability stack, and recovery controls for Kong on ECS/Fargate

### AWS Architecture

The AWS deployment is a container-native, single-service Kong stack with managed observability and recovery controls around it.

Core AWS services and their responsibilities:

- Amazon VPC with two public subnets across two availability zones provides the network boundary for the ALB, ECS task ENIs, and EFS mount targets.
- Application Load Balancer is the only public entry point and routes external traffic to Kong proxy on port `8000`. Admin API and Manager listeners exist but are only opened when explicitly enabled.
- Amazon ECS on Fargate runs one task definition that contains four cooperating containers: PostgreSQL, Kong bootstrap, Kong runtime, and the Prometheus agent sidecar.
- Amazon EFS persists the PostgreSQL data directory so Kong configuration state survives task replacement and can be restored independently of the ECS task lifecycle.
- AWS Secrets Manager stores the PostgreSQL password and Kong Manager secrets and injects them into the task at runtime.
- Amazon Managed Service for Prometheus receives remote-written metrics from the sidecar and stores them outside the task.
- Amazon Managed Grafana queries AMP and serves the operator dashboards.
- Amazon CloudWatch Logs collects logs from `postgres`, `kong-bootstrap`, `kong`, and `amp-collector`.
- AWS Backup protects the EFS file system that holds PostgreSQL data.

How the AWS services work together:

- Request path:
  `Client -> ALB -> Kong proxy in ECS/Fargate -> upstream service`
- Configuration bootstrap path:
  `Terraform renders Kong config -> Kong bootstrap container runs migrations -> config is imported into PostgreSQL -> Kong runtime starts against PostgreSQL`
- State path:
  `PostgreSQL writes to EFS -> AWS Backup snapshots EFS -> recovery can restore data before ECS is redeployed`
- Secrets path:
  `Secrets Manager -> ECS task injection -> PostgreSQL and Kong containers consume secrets at start time`
- Observability path:
  `Kong Prometheus plugin -> Kong internal Status API -> Prometheus sidecar in agent mode -> AMP remote write -> AMG dashboards`
- Incident path:
  `CloudWatch logs + AMP metrics + AMG dashboards -> operator diagnosis -> ECS rollback or EFS restore depending on failure mode`

Container interaction inside the ECS task:

- `postgres` starts first and exposes a task-local database endpoint.
- `kong-bootstrap` waits for PostgreSQL health, runs Kong migrations, and imports the declarative configuration into PostgreSQL.
- `kong` waits for both PostgreSQL health and bootstrap success before serving traffic through the ALB.
- `amp-collector` scrapes Kong's internal Status API on a task-local port and remote-writes those metrics to AMP.

Operational posture:

- Kong runs in PostgreSQL-backed mode, not DB-less mode.
- Management endpoints are not publicly exposed unless `publish_admin_api` or `publish_manager_ui` is enabled.
- Metrics collection is isolated from the public management surface by scraping the internal Status API inside the task.
- The Prometheus collector runs in agent mode and forwards data to AMP instead of keeping a full local TSDB.
- Recovery is centered on EFS persistence and AWS Backup rather than trying to preserve ECS task instances.
- The ECS service is intentionally constrained to one task because PostgreSQL is task-local even though its data directory is persisted on EFS.

Shared templates keep the Kong deployment model consistent across all targets:

- [terraform/templates/docker-compose.yml.tftpl](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/terraform/templates/docker-compose.yml.tftpl)
- [terraform/templates/docker-kong.yml.tftpl](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/terraform/templates/docker-kong.yml.tftpl)

Design intent:

- Keep the runtime AWS-native and hostless.
- Separate infrastructure provisioning, Kong bootstrap, and observability concerns.
- Make rollback, backup, and recovery explicit rather than implied.
- Preserve a rebuild-from-Git workflow through Terraform.

## Configuration Management

For this AWS branch, Terraform owns the deployment flow end to end:

- renders the Kong declarative configuration used during bootstrap
- defines the ECS task composition and startup ordering
- wires Secrets Manager, EFS, Backup, AMP, AMG, IAM, and CloudWatch together
- bootstraps the AMG data source and dashboard import

Ansible is used for non-AWS targets, while AWS uses ECS bootstrap as the equivalent configuration-management mechanism.

In practice, configuration management is split across these stages:

- Terraform renders the Kong declarative config and injects it into the bootstrap container.
- `kong-bootstrap` applies migrations and imports the config into PostgreSQL before the runtime container starts.
- ECS container dependencies enforce the startup order so Kong does not begin serving traffic against an uninitialized datastore.
- Grafana and AMP configuration is managed from Terraform so the observability path is created alongside the application stack.

Key files:

- [anisible/playbooks/site.yml](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/anisible/playbooks/site.yml)
- [anisible/roles/kong/tasks/main.yml](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/anisible/roles/kong/tasks/main.yml)
- [anisible/roles/observability/tasks/main.yml](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/anisible/roles/observability/tasks/main.yml)
- [anisible/playbooks/group_vars/all.yml](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/anisible/playbooks/group_vars/all.yml)

## Security Hygiene

The AWS deployment favors reducing public exposure and moving secrets and diagnostics into managed services.

- Only the proxy listener is intended to be public by default; Admin API and Manager are published only when explicitly enabled.
- Secrets are not hard-coded in task definitions. PostgreSQL and Kong Manager secrets are stored in Secrets Manager and injected into the task at runtime.
- Metrics scraping stays inside the ECS task by using Kong's internal Status API rather than exposing a public metrics endpoint.
- Grafana access is mediated through AWS SSO / IAM Identity Center and the AMG workspace role configuration.
- CloudWatch centralizes logs instead of depending on shell access to hosts or containers.
- EFS backups and Terraform-driven rebuilds reduce the need for risky in-place manual repairs during incidents.

## Persistent Data

Persistent state in this branch is deliberately narrow and centered on Kong's PostgreSQL datastore.

- PostgreSQL runs as a task-local container inside the ECS task.
- Its data directory is mounted on EFS so task replacement does not automatically destroy Kong state.
- AWS Backup protects that EFS file system on a schedule, which gives the branch a recovery point outside ECS.
- AMP and AMG hold observability data and dashboards outside the application task, so telemetry survives task restarts even when the workload is replaced.
- This persistence model is the reason the ECS service is intentionally kept at a single task: the database process is still local to the task even though its files are durable.

## Operations / Recovery

Day-2 operations in this branch are built around managed service visibility plus explicit recovery paths.

- ECS service events show rollout, health-check, and rollback activity.
- CloudWatch log streams from `postgres`, `kong-bootstrap`, `kong`, and `amp-collector` provide the first troubleshooting surface.
- AMG dashboards and AMP queries show request rate, latency, and scrape health once traffic is flowing.
- ECS deployment circuit breaker provides the automatic rollback path for unhealthy revisions.
- EFS plus AWS Backup provides the data recovery path when the PostgreSQL state is corrupted or lost.
- The repository runbook in [docs/AWS_RECOVERY_RUNBOOK.md](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/docs/AWS_RECOVERY_RUNBOOK.md) documents the operator recovery order and rebuild workflow.

## CI/CD And GitOps Flow

The GitHub Actions workflows implement the validation and deployment side of the GitOps path:

- Terraform validation:
  [.github/workflows/terraform-ci.yml](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/.github/workflows/terraform-ci.yml)
- Ansible lint and syntax check:
  [.github/workflows/ansible-ci.yml](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/.github/workflows/ansible-ci.yml)
- Kong and observability smoke test:
  [.github/workflows/observability-smoke.yml](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/.github/workflows/observability-smoke.yml)
- AWS gated deployment with provider-level Terraform plan tests:
  [.github/workflows/aws-deploy.yml](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/.github/workflows/aws-deploy.yml)

Current pipeline stages demonstrated:

- Validate Terraform formatting and configuration
- Validate Ansible playbooks and roles
- Boot Kong locally in CI
- Boot Prometheus and Grafana locally in CI
- Verify Grafana health
- Verify Prometheus can scrape Kong metrics
- Wait for Terraform CI, Ansible CI, and observability smoke test to succeed for the same commit on `release/aws-observability`
- Run a real AWS `terraform init`, `terraform validate`, and `terraform plan` before deployment
- Apply `terraform/environments/aws` automatically after the AWS plan passes
- Upload logs and summaries as workflow artifacts

Safe change practices included:

- Validation before deployment
- Independent workflow checks for branch protection
- Provider-level AWS `terraform plan` before `terraform apply`
- Smoke test of the observability chain, not just syntax
- Artifacts and summaries for failed runs

AWS deployment workflow prerequisites:

- GitHub Actions secret `TF_API_TOKEN`
- HCP Terraform workspace `cp-dre-aws` must exist in organization `CP-DRE` or the values set in `TFC_ORGANIZATION` and `TFC_AWS_WORKSPACE`
- HCP Terraform workspace `cp-dre-aws` must use remote execution mode with operations enabled
- AWS provider credentials must be configured as environment variables or variable set entries in the HCP Terraform workspace, not in GitHub Actions
- Optional repository or environment variables `TFC_ORGANIZATION` and `TFC_AWS_WORKSPACE`
- Optional GitHub Environment named `aws` if you want approval gates on the apply job

## Observability Approach

The AWS observability path is split between in-task collection and managed AWS backends.

Components:

- Kong `prometheus` plugin exposes metrics from inside the ECS task
- Prometheus sidecar runs in agent mode and scrapes Kong's internal Status API
- Amazon Managed Service for Prometheus stores and serves the metric series
- Amazon Managed Grafana provides dashboards and Explore queries
- CloudWatch Logs captures container logs for runtime troubleshooting

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

1. Check the AMG dashboard or Explore query for `up{job="kong-admin",scrape_target="kong"}`.
2. Confirm sample traffic is reaching the ALB and Kong proxy.
3. Inspect `amp-collector` and `kong` log streams in CloudWatch.
4. Check ECS service events for deployment health or rollback activity.
5. If the service is healthy but metrics are missing, validate the AMP datasource and query path in Grafana.

## Resiliency Design

The design focuses on simple, observable failure handling rather than high-availability clustering.

Failure scenarios covered by the design:

1. Application failure:
   Kong container stops or the ECS service fails health checks.
   Expected behavior: ECS marks the deployment unhealthy and can roll back automatically through the deployment circuit breaker.
   Recovery: inspect ECS service events and CloudWatch logs, then redeploy or roll back to the last known-good Terraform commit.

2. Dependency failure:
   Upstream service is unreachable or slow.
   Expected behavior: Kong request errors and latency metrics increase in AMP and Grafana.
   Recovery: inspect upstream reachability, adjust routing, or roll back the upstream-related change.

3. Misconfiguration:
   Broken declarative config or invalid infrastructure change is deployed.
   Expected behavior: CI or Terraform validation should fail before rollout; if it reaches ECS, the service should fail health checks or stop producing expected traffic/metrics.
   Recovery: fix the configuration in Git and redeploy, or re-apply the last known-good commit.

4. State failure:
   PostgreSQL data becomes damaged or unavailable.
   Expected behavior: Kong bootstrap or runtime fails against the persisted data path.
   Recovery: restore the EFS-backed PostgreSQL data through AWS Backup, then redeploy the ECS service.

5. Telemetry failure:
   The Prometheus sidecar cannot scrape Kong or remote-write to AMP.
   Expected behavior: `up{job="kong-admin",scrape_target="kong"}` drops, dashboards go blank, and `amp-collector` logs show scrape or remote-write errors.
   Recovery: inspect `amp-collector` and `kong` logs in CloudWatch, then validate the Status API scrape path, IAM permissions, and AMG datasource configuration.

## Failure Demo Assets

The failure walkthroughs now live as runnable test assets under `tests/` instead of being embedded inline in this README.

- Application failure and ECS task replacement:
  stops the current ECS task on purpose, waits for ECS to replace it, and then re-runs the proxy and optional admin checks to confirm service recovery without rebuilding infrastructure.
  [tests/TP_APPLICATION_FAILURE_RECOVERY_V001.py](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/tests/TP_APPLICATION_FAILURE_RECOVERY_V001.py),
  [tests/TP_APPLICATION_FAILURE_RECOVERY_V001.md](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/tests/TP_APPLICATION_FAILURE_RECOVERY_V001.md)
- Git-driven upstream misconfiguration and recovery:
  commits a bad upstream target into the AWS branch, waits for the deployed proxy path to fail, then creates a revert commit and verifies that the deployment recovers after the rollback applies.
  [tests/TP_MISCONFIGURATION_RECOVERY_V001.py](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/tests/TP_MISCONFIGURATION_RECOVERY_V001.py),
  [tests/TP_MISCONFIGURATION_RECOVERY_V001.md](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/tests/TP_MISCONFIGURATION_RECOVERY_V001.md)

## Validation Status

Validated in this workspace:

- AWS Terraform configuration has been iterated and documented for ECS, EFS, Backup, Secrets Manager, AMP, and AMG
- Python-based verification scripts were updated to target the AWS deployment shape
- GitHub Actions workflows were added for Terraform, Ansible, observability smoke tests, and AWS deployment

Known limitation:

- End-to-end AWS success still depends on valid HCP Terraform workspace configuration, AWS credentials, and a real deploy target; those runtime dependencies cannot be proven from static repository validation alone.

## Tradeoffs And Assumptions

Tradeoffs:

- AWS uses ECS/Fargate to avoid host management and keep the branch focused on an AWS-native runtime.
- The repository still carries host-based and local smoke-test assets, but the deployment path described here is the ECS/Fargate AWS path.
- Kong runs in DB-backed mode on AWS because the branch now prioritizes persistence, rollback safety, and recovery over the simpler DB-less path.
- Observability focuses on metrics and logs first, without a full tracing stack.

Assumptions:

- AWS credentials are supplied externally through the standard provider chain or HCP Terraform workspace variables.
- The current repository names `anisible/` and `promethusGrafana/` are preserved.
- This repository is assessment-oriented and optimized for clarity and operational intent over production scale.

## Next Steps

Natural extensions if more time were available:

1. Add a lower-cost local or free-tier demo path that mirrors the AWS operational model more closely.
2. Add a repeatable scripted chaos/demo harness for the failure playbooks documented in this README.
3. Harden IAM scope, management endpoint exposure, and secret rotation beyond the current assessment baseline.
