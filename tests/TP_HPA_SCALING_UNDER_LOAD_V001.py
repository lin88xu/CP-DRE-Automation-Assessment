#!/usr/bin/env python3

import json
import os
import subprocess
import time
from typing import Dict

from TP_LOCAL_STACK_VERIFICATION_V001 import (
    KUBECTL_NAMESPACE,
    KONG_HOST_HEADER,
    get_ready_pod_name,
    run_command,
)

HPA_NAME = os.getenv("HPA_NAME", "kong")
DEPLOYMENT_NAME = os.getenv("DEPLOYMENT_NAME", "kong")
LOAD_CONCURRENCY = int(os.getenv("LOAD_CONCURRENCY", "40"))
LOAD_DURATION_SECONDS = float(os.getenv("LOAD_DURATION_SECONDS", "120"))
HPA_SCALE_UP_TIMEOUT_SECONDS = float(os.getenv("HPA_SCALE_UP_TIMEOUT_SECONDS", "180"))
HPA_POLL_INTERVAL_SECONDS = float(os.getenv("HPA_POLL_INTERVAL_SECONDS", "5"))
LOAD_PATH = os.getenv("LOAD_PATH", "/delay/2")
BASELINE_STABILIZATION_TIMEOUT_SECONDS = float(
    os.getenv("BASELINE_STABILIZATION_TIMEOUT_SECONDS", "180"),
)


def get_hpa_snapshot() -> Dict[str, int]:
    result = run_command(
        [
            "kubectl",
            "-n",
            KUBECTL_NAMESPACE,
            "get",
            "hpa",
            HPA_NAME,
            "-o",
            "json",
        ],
    )
    if result.returncode != 0:
        raise RuntimeError(f"failed to query HPA {HPA_NAME}: {result.stderr.strip()}")

    payload = json.loads(result.stdout)
    spec = payload.get("spec", {})
    status = payload.get("status", {})
    return {
        "min_replicas": spec.get("minReplicas", 1),
        "max_replicas": spec.get("maxReplicas", 1),
        "current_replicas": status.get("currentReplicas", 0),
        "desired_replicas": status.get("desiredReplicas", 0),
    }


def get_deployment_snapshot() -> Dict[str, int]:
    result = run_command(
        [
            "kubectl",
            "-n",
            KUBECTL_NAMESPACE,
            "get",
            "deployment",
            DEPLOYMENT_NAME,
            "-o",
            "json",
        ],
    )
    if result.returncode != 0:
        raise RuntimeError(f"failed to query deployment {DEPLOYMENT_NAME}: {result.stderr.strip()}")

    payload = json.loads(result.stdout)
    spec = payload.get("spec", {})
    status = payload.get("status", {})
    return {
        "spec_replicas": spec.get("replicas", 0),
        "ready_replicas": status.get("readyReplicas", 0),
        "available_replicas": status.get("availableReplicas", 0),
    }


def get_observed_replicas(hpa_snapshot: Dict[str, int], deployment_snapshot: Dict[str, int]) -> int:
    return max(
        hpa_snapshot["current_replicas"],
        hpa_snapshot["desired_replicas"],
        deployment_snapshot["spec_replicas"],
        deployment_snapshot["ready_replicas"],
    )


def wait_for_baseline() -> tuple[Dict[str, int], Dict[str, int], int]:
    deadline = time.time() + BASELINE_STABILIZATION_TIMEOUT_SECONDS
    last_hpa = get_hpa_snapshot()
    last_deployment = get_deployment_snapshot()
    baseline_target = last_hpa["min_replicas"]

    while True:
        last_hpa = get_hpa_snapshot()
        last_deployment = get_deployment_snapshot()
        observed_replicas = get_observed_replicas(last_hpa, last_deployment)

        if observed_replicas <= baseline_target:
            return last_hpa, last_deployment, baseline_target

        if time.time() >= deadline:
            raise RuntimeError(
                "baseline replicas did not return to the HPA minimum before the load test: "
                f"target={baseline_target}, observed={observed_replicas}. "
                "Wait for scale-down to finish and rerun the test.",
            )

        print(
            "[INFO] Waiting for baseline "
            f"hpa_current={last_hpa['current_replicas']} "
            f"hpa_desired={last_hpa['desired_replicas']} "
            f"deployment_ready={last_deployment['ready_replicas']} "
            f"target={baseline_target}",
        )
        time.sleep(HPA_POLL_INTERVAL_SECONDS)


def validate_in_cluster_proxy_access(prometheus_pod: str) -> None:
    result = run_command(
        [
            "kubectl",
            "-n",
            KUBECTL_NAMESPACE,
            "exec",
            prometheus_pod,
            "--",
            "wget",
            "-qO-",
            "--header",
            f"Host: {KONG_HOST_HEADER}",
            "http://kong.kong.svc.cluster.local:8000/get?source=TP_HPA_SCALING_UNDER_LOAD_V001&request_id=bootstrap",
        ],
    )
    if result.returncode != 0:
        raise RuntimeError(f"failed to verify in-cluster Kong proxy access: {result.stderr.strip()}")

    payload = json.loads(result.stdout)
    args = payload.get("args", {})
    if args.get("source") != "TP_HPA_SCALING_UNDER_LOAD_V001":
        raise RuntimeError("bootstrap proxy request did not include the expected source marker")
    if args.get("request_id") != "bootstrap":
        raise RuntimeError("bootstrap proxy request did not include request_id=bootstrap")


def start_load_processes(prometheus_pod: str) -> list[subprocess.Popen]:
    processes = []
    load_duration = max(1, int(LOAD_DURATION_SECONDS))

    for worker_id in range(1, LOAD_CONCURRENCY + 1):
        shell_script = f"""
i=1
end=$(( $(date +%s) + {load_duration} ))
while [ "$(date +%s)" -lt "$end" ]; do
  wget -qO- --header "Host: {KONG_HOST_HEADER}" "http://kong.{KUBECTL_NAMESPACE}.svc.cluster.local:8000{LOAD_PATH}?source=TP_HPA_SCALING_UNDER_LOAD_V001&worker_id={worker_id}&request_id=$i" >/dev/null 2>&1 || true
  i=$((i + 1))
done
"""
        process = subprocess.Popen(
            [
                "kubectl",
                "-n",
                KUBECTL_NAMESPACE,
                "exec",
                prometheus_pod,
                "--",
                "sh",
                "-c",
                shell_script,
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        processes.append(process)

    return processes


def stop_load_processes(processes: list[subprocess.Popen]) -> None:
    for process in processes:
        if process.poll() is None:
            process.terminate()

    for process in processes:
        if process.poll() is None:
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)


def count_running_processes(processes: list[subprocess.Popen]) -> int:
    return sum(1 for process in processes if process.poll() is None)


def main() -> None:
    baseline_hpa, baseline_deployment, baseline_target = wait_for_baseline()
    prometheus_pod = get_ready_pod_name("app=prometheus")

    baseline_replicas = get_observed_replicas(baseline_hpa, baseline_deployment)
    max_replicas = baseline_hpa["max_replicas"]

    if baseline_replicas >= max_replicas:
        raise RuntimeError(
            f"baseline replicas already at or above HPA max: baseline={baseline_replicas}, max={max_replicas}",
        )

    print(
        "[INFO] Baseline "
        f"hpa_current={baseline_hpa['current_replicas']} "
        f"hpa_desired={baseline_hpa['desired_replicas']} "
        f"deployment_ready={baseline_deployment['ready_replicas']} "
        f"target={baseline_target} "
        f"hpa_max={max_replicas}",
    )
    print(
        "[INFO] Load "
        f"concurrency={LOAD_CONCURRENCY} "
        f"duration_seconds={LOAD_DURATION_SECONDS} "
        f"path={LOAD_PATH} "
        f"scale_up_timeout_seconds={HPA_SCALE_UP_TIMEOUT_SECONDS}",
    )

    scale_up_deadline = time.time() + HPA_SCALE_UP_TIMEOUT_SECONDS
    validate_in_cluster_proxy_access(prometheus_pod)
    processes = start_load_processes(prometheus_pod)

    scaled_up = False
    final_hpa = baseline_hpa
    final_deployment = baseline_deployment

    try:
        while time.time() < scale_up_deadline:
            final_hpa = get_hpa_snapshot()
            final_deployment = get_deployment_snapshot()
            running_workers = count_running_processes(processes)
            print(
                "[INFO] Poll "
                f"hpa_current={final_hpa['current_replicas']} "
                f"hpa_desired={final_hpa['desired_replicas']} "
                f"deployment_ready={final_deployment['ready_replicas']} "
                f"running_workers={running_workers}",
            )

            observed_replicas = get_observed_replicas(final_hpa, final_deployment)
            if observed_replicas > baseline_replicas:
                scaled_up = True
                break

            if running_workers == 0:
                break

            time.sleep(HPA_POLL_INTERVAL_SECONDS)
    finally:
        stop_load_processes(processes)

    print(
        "[INFO] Final "
        f"hpa_current={final_hpa['current_replicas']} "
        f"hpa_desired={final_hpa['desired_replicas']} "
        f"deployment_ready={final_deployment['ready_replicas']} "
        f"running_workers={count_running_processes(processes)}",
    )

    observed_replicas = get_observed_replicas(final_hpa, final_deployment)
    if observed_replicas > max_replicas:
        raise RuntimeError(f"observed replicas exceeded HPA max: observed={observed_replicas}, max={max_replicas}")

    if not scaled_up:
        raise RuntimeError(
            "HPA did not scale above baseline under load: "
            f"baseline={baseline_replicas}, observed={observed_replicas}",
        )

    print("[PASS] HPA scaled above baseline under load")


if __name__ == "__main__":
    main()
