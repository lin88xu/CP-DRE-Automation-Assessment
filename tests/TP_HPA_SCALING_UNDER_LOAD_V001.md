# Test Plan: HPA Scaling Under Load

## 1. Test Plan Identifier

- `TP_HPA_SCALING_UNDER_LOAD_V001`

## 2. Introduction

- Purpose: verify that the Kong HorizontalPodAutoscaler scales the local deployment above its baseline replica count under sustained proxy load.
- Scope: local Minikube runtime only, focused on HPA scale-up behavior for the Kong deployment.
- Basis: the local runtime deploys a Kubernetes `HorizontalPodAutoscaler` for Kong backed by the Minikube `metrics-server` addon.
- Assessment relevance: this is the clearest local demonstration that the system reacts to runtime pressure instead of remaining a static deployment.

## 3. Test Items

- Kong proxy on `http://127.0.0.1:8000`
- Kong deployment in namespace `kong`
- Kong `HorizontalPodAutoscaler`
- Minikube `metrics-server`

## 4. Features To Be Tested

- Baseline HPA and deployment replica counts can be queried successfully
- Sustained concurrent traffic can be sent through the Kong proxy
- The HPA responds to load by increasing the desired or current replica count above baseline
- The scaled replica count does not exceed the configured HPA maximum

## 5. Features Not To Be Tested

- HPA scale-down behavior after load stops
- Cloud deployment paths
- Exact latency, throughput, or error-budget thresholds
- Grafana dashboard content

## 6. Test Approach

- Run a dedicated Python script from the repository root after the local stack is up.
- Wait for Kong to settle back to the HPA minimum replica count before starting the load phase.
- The script captures the baseline HPA state and starts concurrent in-cluster proxy traffic from the Prometheus pod.
- The script polls the Kong HPA and deployment status until scale-up is observed or the timeout is reached.
- Pass when the HPA or deployment replica count increases above baseline within the configured timeout.
- Run this after the basic verification and dashboard-content checks to show progressive evidence: healthy deployment, meaningful observability, then observable scaling behavior.

## 7. Item Pass/Fail Criteria

- Pass:
  the Kong HPA scales above the baseline replica count before the timeout, and the target replica count stays within the configured HPA maximum.
- Fail:
  the HPA does not scale above baseline, the stack is unreachable, or the load run cannot be sustained long enough to observe scaling.

## 8. Suspension And Resumption Criteria

- Suspend if the local runtime is down, the Kong proxy is unreachable, or the Kong deployment is already at the HPA maximum before the test begins.
- Resume after the local runtime is healthy and the Kong baseline replica count is below the HPA maximum.

## 9. Test Deliverables

- This test plan
- `tests/TP_HPA_SCALING_UNDER_LOAD_V001.py`
- Console output from the HPA scale-up test run

## 10. Environmental Needs

- Local runtime deployed with `./local-runtime.sh up`
- Python 3 available
- `kubectl` available in `PATH`
- A ready Prometheus pod in namespace `kong` that can reach `kong.kong.svc.cluster.local:8000`

## 11. Responsibilities

- Operator:
  deploy the stack and run the HPA test script.
- HPA test script:
  generate proxy load, poll the HPA state, and exit non-zero on failure.

## 12. Risks And Contingencies

- If the Kong deployment is already scaled near the HPA maximum, the test may not have enough headroom to prove additional scale-up.
- Kong may still be scaled above its minimum from a previous load run, which delays the start of the test.
- Local machine limits or stale port-forwards may cap the amount of traffic that reaches Kong.
- Contingency:
  wait for Kong to cool down to baseline, rerun `./local-runtime.sh up` if needed, then rerun the HPA test.

## 13. Approval

- Informal approval for assessment use by the repository operator.
