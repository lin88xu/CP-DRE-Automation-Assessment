# Test Plan: Dashboard Content Correctness

## 1. Test Plan Identifier

- `TP_DASHBOARD_CONTENT_CORRECTNESS_V001`

## 2. Introduction

- Purpose: verify that Grafana exposes the expected provisioned Kong dashboard content, not just Grafana service health.
- Scope: Grafana datasource configuration, dashboard provisioning metadata, dashboard variables, panel layout, and key Prometheus expressions used by the provisioned Kong dashboard.
- Basis: the local stack provisions the official Kong Grafana dashboard and a Prometheus datasource into Grafana.

## 3. Test Items

- Grafana on `http://127.0.0.1:3000`
- Prometheus datasource provisioned in Grafana
- Provisioned dashboard `Kong (official)`
- Dashboard source file `kong/kong/plugins/prometheus/grafana/kong-official.json`

## 4. Features To Be Tested

- Grafana API authentication succeeds with the local default credentials
- The Prometheus datasource exists with the expected UID and URL
- The `Kong (official)` dashboard exists with the expected UID and is marked as provisioned
- The live dashboard contains the expected template variables
- The live dashboard contains the expected panel titles and Prometheus expressions

## 5. Features Not To Be Tested

- HPA scaling behavior under load
- Prometheus scrape health beyond what is needed to load dashboard metadata
- Dashboard visual styling or pixel-level layout
- Alert delivery routing outside Grafana

## 6. Test Approach

- Run a dedicated Python verification script from the repository root after the local stack is up.
- Use Grafana's authenticated HTTP API to inspect the live datasource and dashboard objects.
- Compare the live dashboard against key invariants from the provisioned dashboard definition.
- Fail if required dashboard content, variables, datasource bindings, or Prometheus expressions are missing.

## 7. Item Pass/Fail Criteria

- Pass:
  the Grafana datasource and dashboard exist, are provisioned correctly, and expose the expected content structure.
- Fail:
  Grafana authentication fails, the datasource or dashboard is missing, or required dashboard content differs from expectations.

## 8. Suspension And Resumption Criteria

- Suspend if the local runtime is down or Grafana is unreachable.
- Resume after `./local-runtime.sh up` has completed and Grafana is reachable on `127.0.0.1:3000`.

## 9. Test Deliverables

- This test plan
- `tests/TP_DASHBOARD_CONTENT_CORRECTNESS_V001.py`
- Console output from the dashboard-content verification run

## 10. Environmental Needs

- Local runtime deployed with `./local-runtime.sh up`
- Python 3 available
- Grafana reachable on `http://127.0.0.1:3000`
- Grafana credentials available, defaulting to `admin/admin`

## 11. Responsibilities

- Operator:
  deploy the stack and run the dashboard-content verification script.
- Dashboard-content verification script:
  query Grafana APIs and exit non-zero on content mismatches.

## 12. Risks And Contingencies

- Grafana may be healthy while the provisioned dashboard has not finished loading yet.
- Local port-forwards may drop and make the Grafana API appear unavailable.
- Contingency:
  rerun `./local-runtime.sh up`, wait briefly for Grafana provisioning, then rerun the verification script.

## 13. Approval

- Informal approval for assessment use by the repository operator.
