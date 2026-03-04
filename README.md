# CP DRE Automation Assessment

This repository packages Kong Gateway as the application under assessment and wraps it with infrastructure automation, configuration management, CI/CD, and observability.

The same deployment model is intended to work across:

- Local
- AWS
- Azure

## Prerequisites

Before running the local deployment flow yourself, make sure these are installed on the machine where you will run Terraform and Ansible:

- `git`
- `docker`
- `terraform`
- `python3`
- `pip`
- `ansible` / `ansible-playbook`

Local deployment assumptions:

- Docker daemon is running and your user can access it
- You have `sudo` access for the Ansible `become` steps
- Internet access is available to pull container images and packages
- If you run from WSL under `/mnt/c/...`, Ansible may ignore the local `ansible.cfg` unless `ANSIBLE_CONFIG` is set explicitly

Useful preflight checks:

```bash
docker version
terraform version
ansible-playbook --version
python3 --version
```

## Architecture Overview

The solution is organized as a layered delivery model:

1. Terraform provisions the target environment.
2. Ansible configures the target host and deploys the application and observability stack.
3. Kong runs as the API gateway and management plane.
4. Prometheus scrapes Kong metrics.
5. Grafana visualizes service health and request behavior.
6. GitHub Actions validates Terraform, lints Ansible, smoke-tests the observability path, and exercises the Minikube HPA path under load.

High-level flow:

```text
Git Push / Pull Request
        |
        v
GitHub Actions
  - Terraform validate
  - Ansible lint
  - Minikube HPA smoke test
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
  - Local: Terraform handoff -> Ansible + Minikube + HPA
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
  - Prometheus: 9090
  - Grafana: 3000
```

## Operations / Recovery

Primary operator entrypoints:

- Local deploy or teardown:
  `./local-runtime.sh up`, `./local-runtime.sh down`, `./local-runtime.sh status`
- Local guarded deploy with automated rollback:
  `./local-runtime.sh up --verify --auto-rollback`
- Local manual rollback to the last verified-good snapshot:
  `./local-runtime.sh rollback`
- Local automated detection and guarded recovery:
  `./auto-remediation.py detect` or `./auto-remediation.py remediate`
- Persistent-data backup and restore:
  `./persistent-data.sh backup <local-minikube|deployment-kong|observability|azure-host-kong>`
  and `./persistent-data.sh restore <stack> --input-dir <backup-dir>`
- Major-outage platform rebuild:
  `./terraform/disaster-recovery.sh <local|aws|azure> rebuild`

For the full recovery procedures and environment-specific rebuild guidance, see
[docs/RECOVERY_RUNBOOK.md](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/docs/RECOVERY_RUNBOOK.md).

Recommended local automation flow:

```bash
./auto-remediation.py detect
./auto-remediation.py remediate
./auto-remediation.py remediate --allow-restore --backup-before-destructive
./auto-remediation.py watch --interval-seconds 300 --allow-restore --stop-on-failure
```

- `detect` is passive and records evidence only.
- `remediate` first attempts a safe redeploy using the existing verified deploy and rollback path.
- `--allow-restore` permits restoring the latest `local-minikube` backup if safe redeploy is not enough.
- `--allow-disaster-recovery` permits a full local rebuild through `./terraform/disaster-recovery.sh local rebuild`.
- `watch` repeats the same logic on a timer and writes evidence under `.auto-remediation/`.

## Persistent Data

The current active local runtime is the Minikube-backed path behind
`./local-runtime.sh`. In that path:

- Kong is DB-less
- Prometheus stores its TSDB on a PersistentVolumeClaim
- Grafana stores its SQLite state on a PersistentVolumeClaim

That means the local stack is mixed-mode:

- Kong remains rebuild-oriented
- Prometheus and Grafana now retain local state across pod restarts and cluster
  reconciliations
- backup and restore is available for those local Minikube PVCs when you need
  point-in-time recovery

The persistent-data backup and restore automation covers:

- local Minikube PVC-backed Prometheus and Grafana data
- Docker-volume surfaces in this repository:
  `deployment/kong/docker-compose.yml`,
  `promethusGrafana/docker-compose.yml`,
  and `/opt/kong` on the Azure host deployment

Use the helper script:

```bash
./persistent-data.sh inspect local-minikube
./persistent-data.sh backup local-minikube
./persistent-data.sh restore local-minikube --input-dir .backups/<backup-dir>
./persistent-data.sh inspect local-compose
./persistent-data.sh backup deployment-kong
./persistent-data.sh backup observability
./persistent-data.sh restore deployment-kong --input-dir .backups/<backup-dir>
./persistent-data.sh restore observability --input-dir .backups/<backup-dir>
```

On the Azure host:

```bash
./persistent-data.sh backup azure-host-kong --output-dir /var/backups/kong
./persistent-data.sh restore azure-host-kong --input-dir /var/backups/kong/<backup-dir>
```

For the full backup and restore procedures, including what must still be backed
up outside the repository such as Terraform state and cloud credentials, see
[docs/RECOVERY_RUNBOOK.md](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/docs/RECOVERY_RUNBOOK.md#L812).

## Repository Layout

```text
.
├── README.md
├── .github/workflows/
│   ├── ansible-ci.yml
│   ├── minikube-hpa-smoke.yml
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
├── minikube/
│   └── manifests/
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
  [.github/workflows/minikube-hpa-smoke.yml](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/.github/workflows/minikube-hpa-smoke.yml),
  [.github/workflows/observability-smoke.yml](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/.github/workflows/observability-smoke.yml)
- Application and automation code:
  [deployment/kong/](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/deployment/kong),
  [kong/](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/kong),
  [anisible/](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/anisible),
  [promethusGrafana/](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/promethusGrafana)
- Recovery runbook:
  [docs/RECOVERY_RUNBOOK.md](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/docs/RECOVERY_RUNBOOK.md)

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
- Installs Minikube and `kubectl` for the local runtime
- Applies Kubernetes manifests for Kong, the sample upstream service, and a HorizontalPodAutoscaler

Scope note:

- Ansible is the deployment layer for the local and Azure host-based paths.
- The local path uses Terraform to generate the Ansible inventory and variables handoff before Ansible deploys the Minikube-backed local stack.
- The AWS target is container-native and packages Kong directly into ECS/Fargate with Terraform.

Key files:

- [anisible/playbooks/site.yml](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/anisible/playbooks/site.yml)
- [anisible/roles/kong/tasks/main.yml](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/anisible/roles/kong/tasks/main.yml)
- [anisible/roles/minikube/tasks/main.yml](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/anisible/roles/minikube/tasks/main.yml)
- [anisible/roles/observability/tasks/main.yml](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/anisible/roles/observability/tasks/main.yml)
- [anisible/playbooks/group_vars/all.yml](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/anisible/playbooks/group_vars/all.yml)
- [minikube/README.md](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/minikube/README.md)

## CI/CD And GitOps Flow

The current GitHub Actions workflows on this branch cover validation and local smoke testing:

- Terraform validation:
  [.github/workflows/terraform-ci.yml](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/.github/workflows/terraform-ci.yml)
- Ansible lint and syntax check:
  [.github/workflows/ansible-ci.yml](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/.github/workflows/ansible-ci.yml)
- Minikube smoke test for the HPA path:
  [.github/workflows/minikube-hpa-smoke.yml](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/.github/workflows/minikube-hpa-smoke.yml)
- Kong and observability smoke test:
  [.github/workflows/observability-smoke.yml](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/.github/workflows/observability-smoke.yml)

Current pipeline stages demonstrated:

- Validate Terraform formatting, `init -backend=false`, and `validate` across `local`, `aws`, and `azure`
- Validate Ansible playbooks with `ansible-playbook --syntax-check` and `ansible-lint`
- Validate the Kong and observability Docker Compose definitions
- Deploy the local Minikube runtime in CI
- Run the local post-deployment verification script
- Verify provisioned Grafana dashboard content beyond basic service health
- Exercise the Kong HPA path under load with a dedicated Minikube smoke workflow
- Boot Kong locally in CI and verify `/status` and `/metrics`
- Boot Prometheus and Grafana locally in CI
- Verify Grafana health and Prometheus scrape health for `kong-admin`
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
  Note: per-route and per-service views are derived from labels on `kong_http_requests_total`, `kong_kong_latency_ms`, `kong_upstream_latency_ms`, `kong_request_latency_ms`, and `kong_bandwidth_bytes`; those series appear only after proxy traffic hits Kong.
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
- [kong-official.json](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/kong/kong/plugins/prometheus/grafana/kong-official.json)
- [TP_LOCAL_STACK_VERIFICATION_V001.py](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/tests/TP_LOCAL_STACK_VERIFICATION_V001.py)
- [TP_DASHBOARD_CONTENT_CORRECTNESS_V001.py](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/tests/TP_DASHBOARD_CONTENT_CORRECTNESS_V001.py)
- [TP_DASHBOARD_CONTENT_CORRECTNESS_V001.md](/mnt/c/Users/linxu/Documents/Workspaces/CP-DRE-Automation-Assessment/tests/TP_DASHBOARD_CONTENT_CORRECTNESS_V001.md)

Verification assets:

- `python3 tests/TP_LOCAL_STACK_VERIFICATION_V001.py`
  Validates Kong Admin, Kong Proxy, Prometheus, and Grafana health on the local stack.
- `python3 tests/TP_DASHBOARD_CONTENT_CORRECTNESS_V001.py`
  Validates the provisioned Grafana Prometheus datasource and the live `Kong (official)` dashboard content.
- `python3 -u tests/TP_HPA_SCALING_UNDER_LOAD_V001.py`
  Drives load through Kong and checks that the HPA scales above baseline.

Operator investigation path:

1. Check Grafana dashboard health and request rate.
2. Check Prometheus target status for `kong-admin`.
3. Query Kong `/status` and `/metrics`.
4. Inspect runtime logs from Docker Compose or `kubectl logs` if the Minikube runtime is in use.

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
   Recovery: fix config in Git and redeploy, or use the local automated rollback path to return to the last verified-good commit.

4. Telemetry failure:
   Prometheus cannot scrape Kong metrics.
   Expected behavior: Prometheus target becomes `down` and alerts fire.
   Recovery: inspect Kong Admin API, networking, or plugin configuration.

## Local Usage

Terraform handoff plus Ansible deployment:

```bash
cd <repo-root>

./local-runtime.sh
```

The script wraps the local Terraform handoff and the Ansible playbooks into a
single entrypoint. It deploys the Minikube-backed local runtime, handles the
localhost port-forwards, and supports:

```bash
./local-runtime.sh toggle
./local-runtime.sh up
./local-runtime.sh down
./local-runtime.sh rollback
./local-runtime.sh status
```

`toggle` turns the local runtime off when it is already active, and starts it when it is not.

Automated rollback execution is available for the local stack:

```bash
./local-runtime.sh up --verify
./local-runtime.sh up --verify --auto-rollback
./local-runtime.sh rollback
./auto-remediation.py detect
./auto-remediation.py remediate
./auto-remediation.py remediate --allow-restore --allow-disaster-recovery
```

- `up --verify` runs the local post-deployment verification scripts and records the current clean git commit as the last verified-good snapshot.
- `up --verify --auto-rollback` attempts the deployment, runs verification, and if either step fails it redeploys the last verified-good snapshot from a detached git worktree.
- `rollback` manually redeploys the last verified-good snapshot.
- `auto-remediation.py detect` checks the local runtime, localhost access, verification scripts, and Prometheus alert state without changing the environment.
- `auto-remediation.py remediate` classifies the live local stack, attempts a safe redeploy first, and can optionally escalate to backup restore and full local rebuild.

The remediation controller writes timestamped evidence and command logs under
`.auto-remediation/`. It is intended for the local Minikube path only; AWS and
Azure rebuilds remain operator-driven because they are higher-blast-radius
actions.

Rollback snapshots are recorded only from clean git commits, so a dirty working tree will deploy normally but will not overwrite the last verified-good snapshot.

For local runs, `./local-runtime.sh up` prompts for the sudo password used by
Ansible `become`, which is required because the playbook installs packages and
writes under `/opt`.

The local runtime installs a local Kubernetes cluster, deploys Kong and `httpbin`,
and creates a HorizontalPodAutoscaler backed by the Minikube `metrics-server` addon.

On local Linux/WSL with the Minikube `docker` driver, the reported node
IP is on Docker's internal network and is not directly reachable from your
browser. `./local-runtime.sh up` starts the needed localhost port-forwards
automatically, which map the local runtime to:

- Grafana: `http://127.0.0.1:3000`
- Prometheus: `http://127.0.0.1:9090`
- Kong Proxy: `http://127.0.0.1:8000`
- Kong Admin API: `http://127.0.0.1:8001`
- Kong Manager UI: `http://127.0.0.1:8002`

If you deploy through `./local-runtime.sh up`, those localhost
port-forwards are started automatically and cleaned up by
`./local-runtime.sh down`.

## Validation Status

Validated locally in this workspace:

- Terraform installed locally and `local` and `azure` environments validated
- Ansible installed locally and linted successfully
- Kong local stack starts and exposes `/status` and `/metrics`
- Prometheus scrapes Kong metrics successfully
- Grafana health is healthy
- Grafana dashboard content verification passes against the provisioned `Kong (official)` dashboard
- GitHub Actions workflows are present for Terraform, Ansible, observability smoke tests, and Minikube HPA smoke testing
- The local Ansible playbooks now target a single Minikube-backed local runtime
- Automated rollback execution is implemented in `./local-runtime.sh` for verified local deployments
- Automated local failure detection and guarded recovery is implemented in `./auto-remediation.py`
- Persistent-data backup and restore automation is implemented in `./persistent-data.sh`, including local Minikube PVCs for Prometheus and Grafana

Known limitation from local validation:

- Live AWS and Azure plans still require real cloud credentials and environment-specific inputs outside this repository.

## Tradeoffs And Assumptions

Tradeoffs:

- AWS uses ECS/Fargate to avoid host management while Azure remains single-host for now.
- Docker Compose is still used for the Azure host-based path for consistency and speed.
- Kong runs in DB-less mode for simplicity and reproducibility, rather than full database-backed dynamic configuration.
- Observability focuses on metrics and logs first, without a full tracing stack.

Assumptions:

- Local development runs on a machine with Docker available.
- AWS and Azure credentials are supplied externally when using cloud targets.
- The current repository names `anisible/` and `promethusGrafana/` are preserved.
- This repository is assessment-oriented and optimized for clarity and operational intent over production scale.

## Next Steps

Natural extensions if more time were available:

1. Add cloud deployment workflows for Azure plans and applies.
2. Extend automated rollback concepts beyond the local runtime into a real cloud release workflow.
3. Add scheduled backup execution and off-host retention for Azure persistent volumes.
4. Harden secrets handling and reduce default open access in cloud examples.
