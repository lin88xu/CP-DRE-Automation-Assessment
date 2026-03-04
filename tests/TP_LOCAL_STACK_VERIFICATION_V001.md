# Test Plan: Local Stack Verification

## 1. Test Plan Identifier

- `TP_LOCAL_STACK_VERIFICATION_V001`

## 2. Introduction

- Purpose: verify that the deployed local stack is reachable and operational after deployment.
- Scope: Kong proxy and admin endpoints, Prometheus health/target visibility, and Grafana health.
- Basis: local Minikube-backed deployment exposed through the localhost port-forwards managed by `./local-runtime.sh`.

## 3. Test Items

- Kong Proxy on `http://127.0.0.1:8000`
- Kong Admin API on `http://127.0.0.1:8001`
- Prometheus on `http://127.0.0.1:9090`
- Grafana on `http://127.0.0.1:3000`

## 4. Features To Be Tested

- Kong Admin API responds on `/status`
- Kong proxy routes a burst of 50 verification requests to the sample upstream service when `Host: example.com` is supplied
- Prometheus responds on `/-/ready`
- Prometheus exposes the `kong-admin` scrape target
- Grafana responds on `/api/health`

## 5. Features Not To Be Tested

- HPA scaling behavior under load
- Cloud deployment paths
- Authentication and authorization beyond the default local stack
- Dashboard content correctness beyond Grafana service health

## 6. Test Approach

- Run a lightweight Python verification script from the repository root after deployment.
- Use localhost endpoints only.
- Apply bounded retries to tolerate transient port-forward resets during startup.
- Treat any non-`200` response or missing dependency target as a failed verification.

## 7. Item Pass/Fail Criteria

- Pass:
  all checks complete successfully and required endpoints return expected healthy responses.
- Fail:
  any required endpoint is unreachable, unhealthy, or returns unexpected data.

## 8. Suspension And Resumption Criteria

- Suspend if localhost port-forwards are not active or the local runtime is not running.
- Resume after `./local-runtime.sh up` has completed and the localhost ports are listening.

## 9. Test Deliverables

- This test plan
- `tests/TP_LOCAL_STACK_VERIFICATION_V001.py`
- Console output from the verification run

## 10. Environmental Needs

- Local runtime deployed with `./local-runtime.sh up`
- Python 3 available
- Localhost listeners active on ports `3000`, `8000`, `8001`, and `9090`

## 11. Responsibilities

- Operator:
  deploy the stack and run the verification script.
- Verification script:
  perform endpoint checks and exit non-zero on failure.

## 12. Risks And Contingencies

- Local port-forwards may drop and cause transient connection failures.
- Kong may briefly restart or reschedule while the stack is settling.
- Contingency:
  rerun `./local-runtime.sh up` to restore forwards, then rerun the verification script.

## 13. Approval

- Informal approval for assessment use by the repository operator.
