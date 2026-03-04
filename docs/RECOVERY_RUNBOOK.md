# Recovery Runbook

## 1. Purpose

This runbook defines concrete recovery procedures for the CP DRE Automation Assessment repository as it is currently implemented.

It covers:

- local recovery for the Minikube-backed `./local-runtime.sh` stack
- automated local failure detection and guarded recovery through `./auto-remediation.py`
- AWS recovery for the Terraform-managed ECS/Fargate deployment and managed observability components
- Azure recovery for the Terraform-managed single-host VM deployment
- observability recovery for Prometheus and Grafana
- CI recovery for the GitHub Actions validation and smoke workflows
- backup and restore procedures for the persistent data surfaces in this codebase

It does not assume hidden platform automation outside the repository.

## 2. System Model

### 2.1 Deployment paths in this repository

- Local:
  Terraform local handoff -> Ansible -> Minikube -> Kong + Prometheus + Grafana + HPA
- AWS:
  Terraform -> VPC + ALB + ECS/Fargate + Amazon Managed Service for Prometheus + Amazon Managed Grafana
- Azure:
  Terraform -> single Ubuntu VM -> cloud-init -> Docker Compose under `/opt/kong`
- CI:
  GitHub Actions validates Terraform and Ansible, runs an observability smoke workflow, and runs a Minikube HPA smoke workflow

### 2.2 Service inventory

- Kong Proxy:
  local `http://127.0.0.1:8000`, default cloud port `8000`
- Kong Admin API:
  local `http://127.0.0.1:8001`, default cloud port `8001`
- Kong Manager UI:
  local `http://127.0.0.1:8002`, default cloud port `8002`
- Prometheus:
  local `http://127.0.0.1:9090`
- Grafana:
  local `http://127.0.0.1:3000`

### 2.3 Primary recovery principle

This codebase is mostly declarative and rebuild-oriented, but the active local
Minikube path now persists Kong state in Postgres.

- Kong is deployed in PostgreSQL-backed mode in the active local path and in the AWS ECS task, with AWS persisting Postgres data on EFS.
- Local Minikube Kong Postgres, Prometheus, and Grafana use PVC-backed storage.
- AWS recovery is primarily a Terraform re-apply or targeted Terraform replacement exercise.
- Azure is the main path where host-level Docker volumes may require backup and restore.

The default recovery decision should therefore be:

- rebuild first when the environment is declarative and stateless
- restore data only where the implementation actually persists mutable runtime state

## 3. Recovery Objectives And Assumptions

### 3.1 Recovery objectives

- Restore operator access to Kong Admin, Kong Manager, Prometheus, and Grafana.
- Restore the ability to route proxy traffic through Kong.
- Restore observability coverage for Kong request and latency metrics.
- Restore HPA functionality in the local Minikube path.
- Restore CI validation so broken infrastructure code does not merge unnoticed.

### 3.2 Assumptions

- The repository source is available and trusted.
- Terraform state is available for the environment being recovered.
- Container registries and package mirrors are reachable.
- Operators have the credentials required for the target platform:
  local `sudo`, AWS IAM credentials, Azure credentials, and GitHub Actions access as applicable.

## 4. Critical Assets And Persistence Matrix

| Asset | Environment | Persistence model | Recovery action |
| --- | --- | --- | --- |
| Kong declarative config | local, AWS, Azure | Source-controlled | Recreate from repo and redeploy |
| Local Minikube Kong Postgres data | local | PVC-backed | Back up with `persistent-data.sh` or recreate by re-importing source-managed config |
| AWS Kong Postgres data | AWS | EFS-backed | Protect with AWS-native EFS backup or snapshot tooling, or recreate by re-importing source-managed config |
| Kong runtime pods/tasks | local, AWS | Ephemeral | Recreate |
| Local Minikube Prometheus TSDB | local | PVC-backed | Back up with `persistent-data.sh` or recreate if history is not needed |
| Local Minikube Grafana state | local | PVC-backed | Back up with `persistent-data.sh` or recreate if dashboards are fully provisioned |
| Local Minikube dashboard provisioning | local | ConfigMap from source-controlled JSON | Recreate |
| AWS ECS task/service definition | AWS | Terraform-managed | Re-apply or targeted replace |
| AWS AMP workspace and AMG workspace | AWS | Terraform-managed managed services | Re-apply or targeted replace |
| AWS Grafana dashboard bootstrap | AWS | Terraform-managed import step | Re-run Terraform apply |
| Azure Docker Compose files in `/opt/kong` | Azure | Regenerated from Terraform cloud-init | Recreate or copy from backup |
| Azure Docker volumes for Kong/Postgres | Azure | Host-persistent Docker volumes | Back up and restore if needed |
| Local compose smoke volumes | optional local/CI troubleshooting | Docker named volumes | Back up only if you are actively using that path |
| Terraform state | all Terraform targets | Persistent and critical | Must be preserved |
| Variable files, SSH keys, cloud credentials | all | External secrets | Must be preserved outside repo |
| GitHub Actions artifacts | CI | Ephemeral per run | Download during incident if needed |

## 5. Required Access And Tooling

### 5.1 Local operator toolset

- `git`
- `docker`
- `terraform`
- `python3`
- `ansible-playbook`
- `kubectl`
- `minikube`

### 5.2 Cloud operator toolset

- AWS credentials with rights to ECS, ELB, IAM, AMG, AMP, VPC, and CloudWatch
- Azure credentials with rights to resource groups, networking, compute, and public IP resources
- SSH access to the Azure VM using the configured admin user and SSH public key pair

### 5.3 Repo-native verification commands

Use these after any recovery:

```bash
python3 tests/TP_LOCAL_STACK_VERIFICATION_V001.py
python3 tests/TP_DASHBOARD_CONTENT_CORRECTNESS_V001.py
python3 -u tests/TP_HPA_SCALING_UNDER_LOAD_V001.py
```

Use the HPA test only for the local Minikube path.

## 6. Global Incident Workflow

### 6.1 Stabilize

1. Stop making further changes to the affected environment until triage is complete.
2. Record the exact commit being recovered:

```bash
git rev-parse HEAD
git status --short
```

3. Capture the first-failure evidence before restarting anything.

### 6.2 Capture evidence

Local:

```bash
./local-runtime.sh status --no-ask-become-pass
minikube status -p kong-assessment || true
kubectl -n kong get pods,svc,hpa,events
kubectl -n kong describe deploy kong
kubectl -n kong logs deploy/kong --tail=200
kubectl -n kong logs deploy/prometheus --tail=200
kubectl -n kong logs deploy/grafana --tail=200
```

AWS:

```bash
cd terraform/environments/aws
terraform output
```

Then capture provider-side events and logs from ECS, ALB target health, AMP, and AMG.

Azure:

```bash
cd terraform/environments/azure
terraform output
```

Then SSH to the VM and capture:

```bash
ssh <admin_user>@<public_ip>
sudo docker ps
sudo docker logs <container_name> --tail=200
cd /opt/kong && sudo docker-compose ps
cd /opt/kong && sudo docker-compose logs --tail=200
```

CI:

- Download the workflow artifacts before rerunning if the logs are needed:
  `ansible-logs`, `terraform-<environment>-logs`, `observability-smoke-logs`, or `minikube-hpa-smoke-logs`

### 6.3 Classify

Classify the incident as one of:

- deployment bootstrap failure
- Kong service failure
- observability failure
- HPA failure
- infrastructure drift or provisioning failure
- CI validation failure only

### 6.4 Recover

Apply the environment-specific procedure in sections 7 through 10.

For a major outage where the platform must be rebuilt rather than repaired in place, use the repo-native disaster-recovery wrapper:

```bash
./terraform/disaster-recovery.sh local rebuild
./terraform/disaster-recovery.sh aws rebuild -- -var-file=terraform.tfvars
./terraform/disaster-recovery.sh azure rebuild -- -var-file=terraform.tfvars
```

Dry-run rebuild planning is also available:

```bash
./terraform/disaster-recovery.sh aws plan -- -var-file=terraform.tfvars
./terraform/disaster-recovery.sh azure plan -- -var-file=terraform.tfvars
```

Each rebuild writes logs under `terraform/recovery-artifacts/`.

### 6.5 Verify

Always verify:

- Kong Admin is healthy
- Kong Proxy routes traffic
- Prometheus is scraping Kong
- Grafana is reachable
- the expected dashboard is present

### 6.6 Close

Capture:

- root cause
- exact command sequence used
- whether data restore was required
- whether the fix should be codified in Terraform, Ansible, or CI

## 7. Local Minikube Recovery

### 7.1 When to use this section

Use this section when the affected environment is the local stack managed by:

```bash
./local-runtime.sh
```

### 7.2 Expected local architecture

- Terraform only generates the local Ansible handoff files.
- Ansible starts Minikube with the Docker driver.
- Kong runs against PostgreSQL and remains HPA-controlled.
- Prometheus and Grafana run in Kubernetes with PersistentVolumeClaims.
- `./local-runtime.sh up` also starts localhost port-forwards for Kong, Prometheus, and Grafana.

### 7.3 Fast-path health check

```bash
./local-runtime.sh status --no-ask-become-pass
ss -ltn | rg '(:3000|:9090|:8000|:8001|:8002)'
kubectl -n kong get pods,svc,hpa
curl -fsS http://127.0.0.1:8001/status
curl -fsS http://127.0.0.1:3000/api/health
curl -fsS http://127.0.0.1:9090/-/ready
```

### 7.4 Standard recovery

If the cluster exists but localhost access is broken:

```bash
./local-runtime.sh up --no-ask-become-pass
```

This is the preferred first response because it refreshes port-forwards without requiring a full environment rebuild.

### 7.5 Automated local failure detection and guarded recovery

For the local Minikube path, the repository now includes a remediation
controller that reuses the existing verification, rollback, backup, and rebuild
entrypoints:

```bash
./auto-remediation.py detect
./auto-remediation.py remediate
./auto-remediation.py remediate --allow-restore --allow-disaster-recovery --backup-before-destructive
./auto-remediation.py watch --interval-seconds 300 --allow-restore --stop-on-failure
```

Behavior:

- `detect` is passive. It checks runtime state, localhost access, the local
  post-deployment verifier, the Grafana dashboard-content verifier, and
  Prometheus alert state.
- `remediate` runs the same checks, then attempts recovery in a guarded order:
  safe redeploy through `./local-runtime.sh up --verify --auto-rollback`, then
  optional backup restore, then optional full local rebuild.
- `watch` repeats remediation cycles on a timer and writes timestamped evidence
  under `.auto-remediation/`.

Guardrails:

- restore is disabled unless `--allow-restore` is supplied
- full local disaster recovery is disabled unless `--allow-disaster-recovery`
  is supplied
- `--backup-before-destructive` creates a protective `local-minikube` backup
  before restore or rebuild attempts
- automated local remediation still depends on the same `sudo` posture as
  `./local-runtime.sh`; for unattended use, make sure the host can complete the
  Ansible `become` steps non-interactively

If the cluster is unhealthy or pods are stuck:

```bash
./local-runtime.sh down --no-ask-become-pass
./local-runtime.sh up --no-ask-become-pass
```

### 7.5 Automated rollback execution

The local runtime wrapper now supports an automated rollback path based on the last verified-good clean git commit.

Record a verified-good snapshot:

```bash
./local-runtime.sh up --verify
```

Attempt a deploy with automatic rollback on failure:

```bash
./local-runtime.sh up --verify --auto-rollback
```

Manually redeploy the last verified-good snapshot:

```bash
./local-runtime.sh rollback
```

Manually redeploy a specific git ref:

```bash
./local-runtime.sh rollback --rollback-ref <git-ref>
```

How it works:

- verification runs `TP_LOCAL_STACK_VERIFICATION_V001.py` and `TP_DASHBOARD_CONTENT_CORRECTNESS_V001.py`
- successful verified deploys record the current clean git commit in `.local-runtime/rollback/last-known-good.env`
- rollback redeploys that commit from a detached git worktree so the operator's current working tree is not overwritten

Important limitation:

- a dirty working tree can still be deployed, but it will not be recorded as the last verified-good snapshot because it is not reproducible by git ref

### 7.6 Deep clean recovery

Use this only when Minikube is corrupted, the profile is half-created, or repeated normal redeploys fail.

```bash
./local-runtime.sh down --no-ask-become-pass || true
minikube delete -p kong-assessment || true
docker ps -aq --filter "label=name.minikube.sigs.k8s.io=kong-assessment" | xargs -r docker rm -f
rm -rf .local-runtime/port-forward
./local-runtime.sh up --no-ask-become-pass
```

### 7.7 Local component-specific recovery

#### Kong unreachable

```bash
kubectl -n kong get deploy kong
kubectl -n kong describe deploy kong
kubectl -n kong logs deploy/kong --tail=200
kubectl -n kong rollout restart deploy/kong
kubectl -n kong rollout status deploy/kong --timeout=300s
```

#### Prometheus unhealthy

```bash
kubectl -n kong logs deploy/prometheus --tail=200
kubectl -n kong rollout restart deploy/prometheus
kubectl -n kong rollout status deploy/prometheus --timeout=240s
curl -fsS http://127.0.0.1:9090/api/v1/targets
```

#### Grafana unhealthy or dashboard missing

```bash
kubectl -n kong logs deploy/grafana --tail=200
kubectl -n kong rollout restart deploy/grafana
kubectl -n kong rollout status deploy/grafana --timeout=240s
python3 tests/TP_DASHBOARD_CONTENT_CORRECTNESS_V001.py
```

#### HPA not scaling

```bash
kubectl -n kong get hpa kong -o yaml
kubectl -n kong top pods
python3 -u tests/TP_HPA_SCALING_UNDER_LOAD_V001.py
```

If scale-up still does not happen, inspect:

- `metrics-server` availability
- Kong resource requests and limits in `minikube/manifests/kong.yml.j2`
- stale runner or workstation resource exhaustion

### 7.8 Local post-recovery verification

```bash
python3 tests/TP_LOCAL_STACK_VERIFICATION_V001.py
python3 tests/TP_DASHBOARD_CONTENT_CORRECTNESS_V001.py
```

Optionally:

```bash
python3 -u tests/TP_HPA_SCALING_UNDER_LOAD_V001.py
```

## 8. AWS Recovery

### 8.1 Expected AWS architecture

The AWS environment is Terraform-managed and container-native:

- VPC and subnets
- internet-facing ALB
- ECS cluster and Fargate service
- Kong in PostgreSQL-backed mode with a Postgres container whose data is persisted on EFS
- CloudWatch logs
- ECS autoscaling
- Amazon Managed Service for Prometheus
- Amazon Managed Grafana

### 8.2 Primary AWS recovery strategy

Prefer Terraform-led recovery over manual console edits.

The order of preference is:

1. `terraform apply` to converge drift
2. targeted `-replace` for a broken resource
3. controlled destroy-and-recreate only if the environment is beyond repair

### 8.3 AWS fast-path checks

```bash
cd terraform/environments/aws
terraform init
terraform output
```

Record:

- `proxy_url`
- `admin_url`
- `manager_url`
- `grafana_workspace_url`
- `grafana_kong_dashboard_url`
- `amp_prometheus_endpoint`

Check Kong endpoints:

```bash
curl -fsS "$(terraform output -raw admin_url)/status"
```

### 8.4 Standard AWS recovery

Run a normal convergence:

```bash
cd terraform/environments/aws
terraform init
terraform plan
terraform apply
```

Use this when:

- the ALB exists but targets are unhealthy
- Grafana workspace exists but the dashboard bootstrap did not apply cleanly
- ECS service drift is suspected

### 8.5 Targeted AWS replacement

Use targeted replacement for isolated resource corruption.

Examples:

```bash
cd terraform/environments/aws
terraform apply -replace='module.kong.aws_ecs_service.this'
terraform apply -replace='module.kong.aws_ecs_task_definition.this'
terraform apply -replace='module.kong.aws_lb.this'
```

Managed observability rebuilds:

```bash
cd terraform/environments/aws
terraform apply -replace='module.kong.aws_prometheus_workspace.this[0]'
terraform apply -replace='module.kong.aws_grafana_workspace.this[0]'
```

Use observability replacements only when you accept the impact of recreating those managed workspaces.

### 8.6 AWS full environment rebuild

Use this only during a controlled recovery window and only when Terraform state is intact and the environment truly needs replacement.

Primary automated path:

```bash
./terraform/disaster-recovery.sh aws rebuild -- -var-file=terraform.tfvars
```

Dry-run planning:

```bash
./terraform/disaster-recovery.sh aws plan -- -var-file=terraform.tfvars
```

Manual fallback:

```bash
cd terraform/environments/aws
terraform destroy
terraform apply
```

### 8.7 AWS component-specific recovery

#### Kong service unhealthy

Primary recovery:

```bash
cd terraform/environments/aws
terraform apply -replace='module.kong.aws_ecs_service.this'
```

If a new task definition is required:

```bash
cd terraform/environments/aws
terraform apply -replace='module.kong.aws_ecs_task_definition.this'
```

#### AMP or AMG drift

Primary recovery:

```bash
cd terraform/environments/aws
terraform apply
```

If the dashboard bootstrap step drifted but the workspace still exists, a normal `terraform apply` should re-run the `terraform_data.grafana_dashboard_bootstrap` step when its triggers change.

#### Grafana role assignment issues

Correct the configured Grafana user or group ID variables, then run:

```bash
cd terraform/environments/aws
terraform apply
```

### 8.8 AWS post-recovery verification

Minimum:

```bash
cd terraform/environments/aws
curl -fsS "$(terraform output -raw admin_url)/status"
```

Also verify:

- ALB target health is healthy
- ECS service desired and running counts match
- AMP endpoint is reachable from the managed Grafana datasource
- the `Kong (official)` dashboard is available at `grafana_kong_dashboard_url`

## 9. Azure Recovery

### 9.1 Expected Azure architecture

The Azure path provisions:

- resource group
- virtual network and subnet
- public IP
- network security group
- single Ubuntu VM
- Docker and Docker Compose bootstrapped by cloud-init
- Kong stack deployed under `/opt/kong`

### 9.2 Important Azure recovery note

The Azure path is the main environment in this repo where host-persistent Docker volumes matter.

The host uses:

- `/opt/kong/docker-compose.yml`
- `/opt/kong/docker-kong.yml`
- Docker named volumes for Kong and PostgreSQL data

### 9.3 Azure fast-path checks

```bash
cd terraform/environments/azure
terraform init
terraform output
```

Use the printed `ssh_command`, then on the VM:

```bash
cd /opt/kong
sudo docker-compose ps
sudo docker-compose logs --tail=200
sudo docker ps
curl -fsS http://127.0.0.1:8001/status
```

### 9.4 Standard Azure service recovery

On the VM:

```bash
cd /opt/kong
sudo docker-compose up -d
sudo docker-compose ps
```

If Kong is unhealthy:

```bash
cd /opt/kong
sudo docker-compose restart kong
sudo docker-compose logs kong --tail=200
```

If the database container is unhealthy:

```bash
cd /opt/kong
sudo docker-compose restart kong-db
sudo docker-compose logs kong-db --tail=200
```

### 9.5 Azure host reprovision

When the VM itself is unhealthy or irrecoverable, prefer Terraform replacement:

```bash
cd terraform/environments/azure
terraform apply -replace='module.kong.azurerm_linux_virtual_machine.this'
```

If networking or public IP is the issue, use standard `terraform apply` first, then targeted replacement only if needed.

### 9.6 Azure full environment rebuild

Primary automated path:

```bash
./terraform/disaster-recovery.sh azure rebuild -- -var-file=terraform.tfvars
```

Dry-run planning:

```bash
./terraform/disaster-recovery.sh azure plan -- -var-file=terraform.tfvars
```

Manual fallback:

```bash
cd terraform/environments/azure
terraform destroy
terraform apply
```

Use this only if:

- the VM is unrecoverable
- the network layer is corrupt
- or a clean rebuild is operationally cheaper than in-place host repair

### 9.7 Azure post-recovery verification

From the operator host:

```bash
cd terraform/environments/azure
curl -fsS "$(terraform output -raw admin_url)/status"
```

Then verify:

- proxy routing through `proxy_url`
- Manager UI on `manager_url`
- VM SSH access via `ssh_command`

## 10. Observability Recovery

### 10.1 Symptoms

- Grafana loads but shows no dashboard
- Prometheus is up but `kong-admin` target is down
- Kong Admin works but Grafana is blank
- dashboard-content verification script fails

### 10.2 Local Minikube observability recovery

```bash
kubectl -n kong get pods,svc,configmap
kubectl -n kong logs deploy/prometheus --tail=200
kubectl -n kong logs deploy/grafana --tail=200
kubectl -n kong rollout restart deploy/prometheus
kubectl -n kong rollout restart deploy/grafana
python3 tests/TP_DASHBOARD_CONTENT_CORRECTNESS_V001.py
```

### 10.3 Local compose observability recovery

If you are using the auxiliary compose-based observability stack for smoke testing:

```bash
docker compose --project-directory promethusGrafana -f promethusGrafana/docker-compose.yml down -v
docker compose --project-directory promethusGrafana -f promethusGrafana/docker-compose.yml up -d
```

### 10.4 AWS observability recovery

Use Terraform first:

```bash
cd terraform/environments/aws
terraform apply
```

Then verify:

- AMP workspace output values exist
- AMG workspace URL is reachable
- the Kong dashboard URL is present

## 11. CI Recovery

### 11.1 Terraform CI failure

Workflow:

- `.github/workflows/terraform-ci.yml`

Artifact names:

- `terraform-local-logs`
- `terraform-aws-logs`
- `terraform-azure-logs`

Local reproduction:

```bash
terraform fmt -check -recursive terraform
cd terraform/environments/local && terraform init -backend=false && terraform validate
cd ../aws && terraform init -backend=false && terraform validate
cd ../azure && terraform init -backend=false && terraform validate
```

### 11.2 Ansible CI failure

Workflow:

- `.github/workflows/ansible-ci.yml`

Artifact name:

- `ansible-logs`

Local reproduction:

```bash
cd anisible
ANSIBLE_CONFIG=./ansible.cfg ANSIBLE_ROLES_PATH=./roles ansible-playbook -i inventories/local/hosts.yml --syntax-check playbooks/site.yml
ANSIBLE_CONFIG=./ansible.cfg ANSIBLE_ROLES_PATH=./roles ansible-lint playbooks/site.yml
```

### 11.3 Observability smoke failure

Workflow:

- `.github/workflows/observability-smoke.yml`

Artifact name:

- `observability-smoke-logs`

Local reproduction:

```bash
docker compose --project-directory deployment/kong -f deployment/kong/docker-compose.yml up -d
docker compose --project-directory promethusGrafana -f promethusGrafana/docker-compose.yml up -d
curl -fsS http://localhost:8001/status
curl -fsS http://localhost:8001/metrics
curl -fsS http://localhost:3000/api/health
curl -fsS http://localhost:9090/api/v1/targets
```

### 11.4 Minikube HPA smoke failure

Workflow:

- `.github/workflows/minikube-hpa-smoke.yml`

Artifact name:

- `minikube-hpa-smoke-logs`

Local reproduction:

```bash
./local-runtime.sh up --no-ask-become-pass
python3 tests/TP_LOCAL_STACK_VERIFICATION_V001.py
python3 tests/TP_DASHBOARD_CONTENT_CORRECTNESS_V001.py
python3 -u tests/TP_HPA_SCALING_UNDER_LOAD_V001.py
./local-runtime.sh down --no-ask-become-pass
```

### 11.5 CI rerun rule

Do not rerun immediately without first reading the failing artifact or the failing step log.

Minimum requirement before rerun:

- identify the failing step name
- identify whether the failure is syntax, provisioning, rollout, port-forwarding, or verification
- confirm whether the same failure reproduces locally

## 12. Backup And Restore Procedures

### 12.1 What must be backed up

Mandatory backups:

- Terraform state for AWS and Azure
- environment-specific `.tfvars` or secret variable sources
- SSH private keys used for Azure access
- cloud credentials and GitHub repository settings outside the repo

Optional backups:

- local Minikube Prometheus and Grafana PVCs if you need to preserve metrics history or Grafana state across rebuilds
- AWS EFS backups or snapshots if you need point-in-time recovery of the Kong Postgres data path
- Azure host Docker volumes if you need point-in-time recovery of host-persistent data
- local compose volumes only if you intentionally use the compose-based stacks outside CI

### 12.2 What does not require backup

Do not spend effort backing up these local Minikube runtime assets:

- Kong pod state
- provisioned dashboard ConfigMaps

Kong remains stateless in this implementation and should be recreated. Local
Prometheus and Grafana data is now PVC-backed and can be backed up with the
scripted path below when you need point-in-time recovery.

### 12.3 Local Minikube backup procedure

Primary scripted path:

```bash
./persistent-data.sh inspect local-minikube
./persistent-data.sh backup local-minikube
```

This script:

- verifies the Prometheus and Grafana PVCs exist in the `kong` namespace
- creates a timestamped backup directory under `.backups/`
- mounts each PVC through a temporary helper pod
- archives the Prometheus TSDB and Grafana data directory into `.tgz` files

Restore path:

```bash
./persistent-data.sh restore local-minikube --input-dir .backups/<local-minikube-backup-dir>
```

The script scales `prometheus` and `grafana` down to zero replicas, restores
the PVC contents, and scales both deployments back up.

Use this backup when you need to retain:

- Prometheus time-series history collected during local testing
- Grafana state written under `/var/lib/grafana`

This backup now preserves local Kong Postgres data in addition to Prometheus
and Grafana state. Source-managed Kong config can still be recreated from the
repository if you choose to rebuild instead of restore.

### 12.4 Azure host backup procedure

Primary scripted path on the Azure VM:

```bash
./persistent-data.sh backup azure-host-kong --output-dir /var/backups/kong
```

This script:

- discovers the Docker volumes owned by the `kong` Compose project
- creates a timestamped backup directory
- archives each volume into a `.tgz`
- also archives `/opt/kong` so the deployed Compose files can be restored with the data

Manual fallback:

On the Azure VM, identify the actual compose-created volume names:

```bash
sudo docker volume ls --format '{{.Name}}' | rg 'kong.*(db-data|kong-data)'
```

Create a backup directory:

```bash
sudo mkdir -p /var/backups/kong
```

Back up a discovered volume:

```bash
VOLUME_NAME='<actual_volume_name>'
BACKUP_NAME="${VOLUME_NAME}-$(date +%Y%m%d%H%M%S).tgz"
sudo docker run --rm \
  -v "${VOLUME_NAME}:/source:ro" \
  -v /var/backups/kong:/backup \
  alpine:3.20 \
  tar -C /source -czf "/backup/${BACKUP_NAME}" .
```

Back up the deployed compose files:

```bash
sudo tar -C /opt -czf /var/backups/kong/opt-kong-files-$(date +%Y%m%d%H%M%S).tgz kong
```

### 12.5 Azure host restore procedure

Primary scripted path on the Azure VM:

```bash
./persistent-data.sh restore azure-host-kong --input-dir /var/backups/kong/<backup-dir>
```

The script stops the Compose stack when possible, restores `/opt/kong` if it was backed up, restores each Docker volume, and starts the stack again.

Manual fallback:

Stop the stack first:

```bash
cd /opt/kong
sudo docker-compose down
```

Create the destination volume if required:

```bash
sudo docker volume create <actual_volume_name>
```

Restore a backup archive into the volume:

```bash
sudo docker run --rm \
  -v "<actual_volume_name>:/restore" \
  -v /var/backups/kong:/backup:ro \
  alpine:3.20 \
  sh -c 'rm -rf /restore/* /restore/.[!.]* /restore/..?* 2>/dev/null || true; tar -C /restore -xzf /backup/<backup_file>.tgz'
```

Restore `/opt/kong` files if needed:

```bash
sudo tar -C /opt -xzf /var/backups/kong/<opt-kong-backup>.tgz
```

Bring the stack back:

```bash
cd /opt/kong
sudo docker-compose up -d
```

### 12.6 Local compose backup procedure

Only use this if you are intentionally running:

- `deployment/kong/docker-compose.yml`
- `promethusGrafana/docker-compose.yml`

Primary scripted path:

```bash
./persistent-data.sh inspect local-compose
./persistent-data.sh backup local-compose
```

This creates separate timestamped backup directories under `.backups/` for:

- `deployment-kong`
- `observability`

Restore them individually:

```bash
./persistent-data.sh restore deployment-kong --input-dir .backups/<deployment-kong-backup-dir>
./persistent-data.sh restore observability --input-dir .backups/<observability-backup-dir>
```

Use `local-compose` only for the optional Docker Compose troubleshooting path.
The primary local runtime now uses the separate `local-minikube` backup path
described above.

## 13. Post-Recovery Validation Checklist

Run the checks that match the recovered environment.

### 13.1 Local Minikube

```bash
python3 tests/TP_LOCAL_STACK_VERIFICATION_V001.py
python3 tests/TP_DASHBOARD_CONTENT_CORRECTNESS_V001.py
```

Optional:

```bash
python3 -u tests/TP_HPA_SCALING_UNDER_LOAD_V001.py
```

### 13.2 AWS

Validate:

- `admin_url/status` returns success
- `proxy_url` can route traffic to the configured host header
- `grafana_workspace_url` is reachable
- `grafana_kong_dashboard_url` opens the expected dashboard

### 13.3 Azure

Validate:

- `admin_url/status` returns success
- `proxy_url` routes traffic
- `manager_url` is reachable
- the VM remains reachable over SSH

## 14. Known Gaps In The Current Codebase

- The local runtime is intentionally ephemeral; it is not designed for durable historical metrics retention.
- Major-outage rebuild automation now exists for local, AWS, and Azure, but only the local path includes post-deploy verification by default.
- Azure recovery can rebuild the platform automatically, but host-level Docker volume restoration still remains a separate operator task when state preservation is required.
- The repo contains both a Minikube runtime and auxiliary compose-based smoke assets; operators must not confuse the two during incident response.
- CI smoke stability depends on runner resource ceilings, especially for Minikube and HPA tests.

These gaps should be treated as design constraints during recovery, not operator error.

## 15. Source References

- `local-runtime.sh`
- `anisible/playbooks/site.yml`
- `anisible/playbooks/teardown.yml`
- `anisible/roles/minikube/tasks/main.yml`
- `minikube/manifests/`
- `terraform/environments/local/`
- `terraform/environments/aws/`
- `terraform/environments/azure/`
- `.github/workflows/`
- `tests/TP_LOCAL_STACK_VERIFICATION_V001.py`
- `tests/TP_HPA_SCALING_UNDER_LOAD_V001.py`
- `tests/TP_DASHBOARD_CONTENT_CORRECTNESS_V001.py`
