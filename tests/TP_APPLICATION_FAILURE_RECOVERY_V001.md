# TP_APPLICATION_FAILURE_RECOVERY_V001

Purpose:

- stop the current ECS task on purpose
- verify the ECS service replaces it automatically
- verify Kong proxy traffic succeeds again after recovery

Run:

```bash
python3 tests/TP_APPLICATION_FAILURE_RECOVERY_V001.py
```

Default assumptions:

- ECS cluster defaults to `kong-aws-cluster`
- ECS service defaults to `kong-aws-service`
- AWS region defaults from `AWS_REGION`, `AWS_DEFAULT_REGION`, or `terraform/environments/aws/terraform.tfvars`

Useful overrides:

```bash
AWS_REGION=ap-southeast-1 \
ECS_CLUSTER_NAME=kong-aws-cluster \
ECS_SERVICE_NAME=kong-aws-service \
python3 tests/TP_APPLICATION_FAILURE_RECOVERY_V001.py
```

Expected result:

- the current ECS task is stopped
- ECS launches a replacement task
- the script waits until the replacement task is healthy
- Kong proxy verification passes again
