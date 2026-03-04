# AWS Recovery Runbook

This branch deploys Kong on AWS in DB-backed mode with these operational constraints:

- Kong runs on ECS/Fargate.
- Kong configuration is imported into PostgreSQL during bootstrap.
- PostgreSQL runs inside the task and persists its data on EFS.
- Secrets are injected from AWS Secrets Manager.
- Amazon Managed Service for Prometheus and Amazon Managed Grafana provide observability.
- The ECS Prometheus sidecar scrapes Kong's internal Status API rather than the public management listener.
- Kong proxy is public by default.
- Kong Admin API and Kong Manager stay unpublished unless you explicitly enable them.

## Rollback Strategy

The AWS deployment now uses the ECS deployment circuit breaker with rollback enabled.
That gives the service an automatic rollback path when a replacement deployment does
not become healthy.

The service is also intentionally pinned to single-task semantics:

- `desired_count = 1`
- `min_capacity = 1`
- `max_capacity = 1`
- `deployment_maximum_percent = 100`
- `deployment_minimum_healthy_percent = 0`

This prevents overlapping task revisions from trying to run the task-local PostgreSQL
database against the same EFS data directory at the same time.

If a bad change has already reached Terraform state, roll back operationally by:

1. Reverting to the last known-good Git commit on `release/aws-observability`.
2. Re-running the AWS deploy workflow or applying Terraform again from that commit.
3. Confirming ECS has returned to a healthy service revision.

## Backup And Recovery

The PostgreSQL data path is persisted on EFS and protected with AWS Backup.

After `terraform apply`, capture these outputs:

```bash
cd terraform/environments/aws
terraform output proxy_url
terraform output admin_url
terraform output grafana_workspace_url
```

Recommended recovery order:

1. Check ECS service health and recent events.
2. Check CloudWatch logs for `kong`, `kong-bootstrap`, `postgres`, and `amp-collector`.
3. If the deployment revision is unhealthy, re-apply the last known-good Terraform commit.
4. If PostgreSQL data is damaged or missing, restore the EFS recovery point through AWS Backup, then redeploy.
5. For a full rebuild, use the repository-native disaster recovery wrapper:

```bash
cd terraform/environments/aws
bash ../../disaster-recovery.sh aws rebuild -- -var-file=terraform.tfvars
```

## Verification

Basic external verification:

```bash
cd terraform/environments/aws
curl -sS -H "Host: example.com" "$(terraform output -raw proxy_url)/" >/dev/null
terraform output -raw grafana_workspace_url
```

If you intentionally enable public management access:

```bash
curl -sS "$(terraform output -raw admin_url)/status"
```

When management access remains unpublished, prefer AWS-native checks:

```bash
aws ecs describe-services \
  --cluster "kong-aws-cluster" \
  --services "kong-aws-service"
```
