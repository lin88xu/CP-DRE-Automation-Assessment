# TP_DASHBOARD_CONTENT_CORRECTNESS_V001

Purpose:

- verify Grafana has the provisioned Prometheus datasource
- verify the provisioned dashboard is present
- verify the live dashboard content matches the source dashboard JSON in the repository

Defaults:

- Grafana URL defaults from `terraform output grafana_workspace_url` when AWS Terraform state is available
- Grafana auth defaults to basic auth with `admin` / `admin` for local Docker Grafana
- Set `GRAFANA_TOKEN` for Amazon Managed Grafana API access
- Datasource name defaults to `Amazon Managed Service for Prometheus` for AWS and `Prometheus` for local
- Provisioning metadata is enforced for local Docker Grafana and disabled by default for AWS, where the dashboard is imported through the Grafana API
- Source dashboard: `promethusGrafana/grafana/dashboards/kong-overview.json`

Run:

```bash
python3 tests/TP_DASHBOARD_CONTENT_CORRECTNESS_V001.py
```

Run against local Docker Grafana:

```bash
GRAFANA_URL=http://127.0.0.1:3000 \
GRAFANA_USER=admin \
GRAFANA_PASSWORD=admin \
python3 tests/TP_DASHBOARD_CONTENT_CORRECTNESS_V001.py
```

Run against Amazon Managed Grafana:

```bash
GRAFANA_URL="$(cd terraform/environments/aws && terraform output -raw grafana_workspace_url)" \
GRAFANA_TOKEN="<grafana-service-account-token>" \
python3 tests/TP_DASHBOARD_CONTENT_CORRECTNESS_V001.py
```
