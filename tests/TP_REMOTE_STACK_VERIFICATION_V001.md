# TP_REMOTE_STACK_VERIFICATION_V001

Purpose:

- verify the currently targeted Kong stack is up
- verify Kong proxy traffic reaches the sample upstream
- skip Prometheus target validation in this script
- skip Grafana health in this script; use the dedicated dashboard verification script when needed

Default behavior:

- Kong proxy defaults to the AWS ALB URL already checked into this repo:
  `http://kong-aws-alb-500175267.ap-southeast-1.elb.amazonaws.com:8000`
- Kong admin defaults from `terraform output admin_url` when public access is enabled
- Grafana is intentionally skipped in this script
- Prometheus is intentionally skipped in this script
- Kong Admin is skipped only when `admin_url` is unavailable for the selected target
- Any check without a reachable URL is reported as `[SKIP]`

Run:

```bash
python3 tests/TP_REMOTE_STACK_VERIFICATION_V001.py
```

Run against remote or local endpoints explicitly:

```bash
KONG_PROXY_URL=http://127.0.0.1:8000 \
KONG_ADMIN_URL=http://127.0.0.1:8001 \
GRAFANA_URL=http://127.0.0.1:3000 \
STACK_TARGET=local \
python3 tests/TP_REMOTE_STACK_VERIFICATION_V001.py
```

Useful AWS overrides:

```bash
KONG_PROXY_URL="$(cd terraform/environments/aws && terraform output -raw proxy_url)" \
python3 tests/TP_REMOTE_STACK_VERIFICATION_V001.py
```
