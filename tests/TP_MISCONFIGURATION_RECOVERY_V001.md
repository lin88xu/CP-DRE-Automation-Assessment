# TP_MISCONFIGURATION_RECOVERY_V001

Purpose:

- introduce a Git-driven upstream misconfiguration on the AWS branch
- wait for the deployed proxy path to fail
- revert the bad change and verify the proxy path recovers

Run:

```bash
python3 tests/TP_MISCONFIGURATION_RECOVERY_V001.py
```

Important behavior:

- this script edits `terraform/environments/aws/terraform.tfvars`
- it creates a Git commit
- it pushes to `release/aws-observability` by default
- it then creates a Git revert commit and pushes again for recovery

Default assumptions:

- target branch is `release/aws-observability`
- the bad upstream URL is `http://127.0.0.1:9`
- the AWS deploy workflow applies branch changes automatically

Useful overrides:

```bash
TARGET_BRANCH=release/aws-observability \
BAD_UPSTREAM_URL=http://127.0.0.1:9 \
DEPLOYMENT_TIMEOUT_SECONDS=1800 \
python3 tests/TP_MISCONFIGURATION_RECOVERY_V001.py
```

Expected result:

- the first pushed commit causes the sample route to return `5xx`
- the revert commit restores the previous upstream configuration
- Kong proxy verification passes again after the recovery deployment finishes
