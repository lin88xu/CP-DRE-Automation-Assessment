#!/usr/bin/env python3

import atexit
import http.client
import json
import os
import shutil
import socket
import subprocess
import time
from http.client import RemoteDisconnected
from typing import Dict, List, Optional, Tuple
from urllib.parse import urlencode, urlparse

KONG_PROXY_URL = os.getenv("KONG_PROXY_URL", "http://127.0.0.1:8000")
KONG_ADMIN_URL = os.getenv("KONG_ADMIN_URL", "http://127.0.0.1:8001")
PROMETHEUS_URL = os.getenv("PROMETHEUS_URL", "http://127.0.0.1:9090")
GRAFANA_URL = os.getenv("GRAFANA_URL", "http://127.0.0.1:3000")
KONG_HOST_HEADER = os.getenv("KONG_HOST_HEADER", "example.com")
PROMETHEUS_TARGET_JOB = os.getenv("PROMETHEUS_TARGET_JOB", "kong-admin")
KUBECTL_NAMESPACE = os.getenv("KUBECTL_NAMESPACE", "kong")
REQUEST_TIMEOUT_SECONDS = float(os.getenv("REQUEST_TIMEOUT_SECONDS", "10"))
MAX_RETRIES = int(os.getenv("MAX_RETRIES", "5"))
RETRY_DELAY_SECONDS = float(os.getenv("RETRY_DELAY_SECONDS", "0.5"))
KONG_PROXY_REQUEST_COUNT = int(os.getenv("KONG_PROXY_REQUEST_COUNT", "50"))
KONG_PROXY_REQUEST_DELAY_SECONDS = float(
    os.getenv("KONG_PROXY_REQUEST_DELAY_SECONDS", "0.1"),
)
PORT_FORWARD_START_TIMEOUT_SECONDS = float(
    os.getenv("PORT_FORWARD_START_TIMEOUT_SECONDS", "20"),
)

PORT_FORWARD_PROCESSES: List[subprocess.Popen] = []


def parse_host_port(url: str) -> Tuple[str, int]:
    parsed = urlparse(url)
    host = parsed.hostname or "127.0.0.1"
    port = parsed.port or (443 if parsed.scheme == "https" else 80)
    return host, port


def is_port_open(host: str, port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(0.5)
        return sock.connect_ex((host, port)) == 0


def cleanup_port_forwards() -> None:
    while PORT_FORWARD_PROCESSES:
        process = PORT_FORWARD_PROCESSES.pop()
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)


def run_command(command: List[str]) -> subprocess.CompletedProcess:
    return subprocess.run(
        command,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def get_ready_pod_name(label_selector: str) -> str:
    result = run_command(
        [
            "kubectl",
            "-n",
            KUBECTL_NAMESPACE,
            "get",
            "pods",
            "-l",
            label_selector,
            "-o",
            "json",
        ],
    )
    if result.returncode != 0:
        raise RuntimeError(f"failed to query pods: {result.stderr.strip()}")

    payload = json.loads(result.stdout)
    for item in payload.get("items", []):
        if item.get("status", {}).get("phase") != "Running":
            continue
        container_statuses = item.get("status", {}).get("containerStatuses", [])
        if container_statuses and all(status.get("ready") for status in container_statuses):
            return item["metadata"]["name"]

    raise RuntimeError(f"no ready pod found for selector {label_selector}")


def kubectl_exec(pod_name: str, command: List[str]) -> str:
    result = run_command(
        [
            "kubectl",
            "-n",
            KUBECTL_NAMESPACE,
            "exec",
            pod_name,
            "--",
            *command,
        ],
    )
    if result.returncode != 0:
        stderr = result.stderr.strip()
        raise RuntimeError(f"kubectl exec failed for {pod_name}: {stderr}")
    return result.stdout


def start_port_forward(name: str, args: List[str], host: str, port: int) -> None:
    if is_port_open(host, port):
        return

    if shutil.which("kubectl") is None:
        raise RuntimeError(
            f"{name} is not reachable on {host}:{port} and kubectl is not available to start a port-forward",
        )

    process = subprocess.Popen(
        ["kubectl", "-n", KUBECTL_NAMESPACE, "port-forward", *args],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    PORT_FORWARD_PROCESSES.append(process)

    deadline = time.time() + PORT_FORWARD_START_TIMEOUT_SECONDS
    while time.time() < deadline:
        if process.poll() is not None:
            raise RuntimeError(f"failed to start port-forward for {name}")
        if is_port_open(host, port):
            return
        time.sleep(0.2)

    raise RuntimeError(f"timed out waiting for port-forward for {name} on {host}:{port}")


def ensure_local_access() -> None:
    kong_proxy_host, kong_proxy_port = parse_host_port(KONG_PROXY_URL)
    kong_admin_host, kong_admin_port = parse_host_port(KONG_ADMIN_URL)
    prometheus_host, prometheus_port = parse_host_port(PROMETHEUS_URL)
    grafana_host, grafana_port = parse_host_port(GRAFANA_URL)

    if kong_proxy_host == "127.0.0.1" and not is_port_open(kong_proxy_host, kong_proxy_port):
        start_port_forward(
            "Kong proxy",
            ["svc/kong", f"{kong_proxy_port}:8000"],
            kong_proxy_host,
            kong_proxy_port,
        )

    if kong_admin_host == "127.0.0.1" and not is_port_open(kong_admin_host, kong_admin_port):
        start_port_forward(
            "Kong admin",
            ["svc/kong", f"{kong_admin_port}:8001"],
            kong_admin_host,
            kong_admin_port,
        )

    if grafana_host == "127.0.0.1" and not is_port_open(grafana_host, grafana_port):
        start_port_forward(
            "Grafana",
            ["svc/grafana", f"{grafana_port}:3000"],
            grafana_host,
            grafana_port,
        )

    if prometheus_host == "127.0.0.1" and not is_port_open(prometheus_host, prometheus_port):
        start_port_forward(
            "Prometheus",
            ["svc/prometheus", f"{prometheus_port}:9090"],
            prometheus_host,
            prometheus_port,
        )


def http_get(url: str, *, headers: Optional[Dict[str, str]] = None) -> Tuple[int, bytes]:
    parsed = urlparse(url)
    host = parsed.hostname or "127.0.0.1"
    port = parsed.port or (443 if parsed.scheme == "https" else 80)
    path = parsed.path or "/"
    if parsed.query:
        path = f"{path}?{parsed.query}"

    last_error = None

    for attempt in range(1, MAX_RETRIES + 1):
        connection = http.client.HTTPConnection(
            host,
            port,
            timeout=REQUEST_TIMEOUT_SECONDS,
        )
        try:
            connection.request("GET", path, headers=headers or {})
            response = connection.getresponse()
            body = response.read()
            return response.status, body
        except (OSError, RemoteDisconnected) as exc:
            last_error = exc
            if attempt == MAX_RETRIES:
                break
            time.sleep(RETRY_DELAY_SECONDS)
        finally:
            connection.close()

    raise RuntimeError(f"request failed after {MAX_RETRIES} attempts: {url}") from last_error


def assert_status(name: str, status: int, expected: int, body: bytes) -> None:
    if status != expected:
        snippet = body.decode("utf-8", errors="replace")[:300]
        raise RuntimeError(f"{name} returned {status}, expected {expected}: {snippet}")


def validate_kong_proxy_response(body: bytes, request_index: int) -> None:
    payload = json.loads(body.decode("utf-8"))
    args = payload.get("args", {})
    if args.get("source") != "TP_LOCAL_STACK_VERIFICATION_V001":
        raise RuntimeError("Kong proxy response did not include the expected upstream echo")
    if args.get("request_index") != str(request_index):
        raise RuntimeError(
            f"Kong proxy response did not include the expected request_index={request_index}",
        )


def verify_kong_admin() -> None:
    try:
        status, body = http_get(f"{KONG_ADMIN_URL}/status")
        assert_status("Kong Admin /status", status, 200, body)
        payload = json.loads(body.decode("utf-8"))
        if "database" not in payload:
            raise RuntimeError("Kong Admin /status response did not include database state")
        return
    except RuntimeError:
        pod_name = get_ready_pod_name("app=kong")
        result = run_command(
            [
                "kubectl",
                "-n",
                KUBECTL_NAMESPACE,
                "exec",
                pod_name,
                "--",
                "kong",
                "health",
            ],
        )
        if result.returncode != 0:
            stderr = result.stderr.strip()
            raise RuntimeError(f"Kong admin verification failed via localhost and pod fallback: {stderr}")


def verify_kong_proxy() -> None:
    if KONG_PROXY_REQUEST_COUNT < 1:
        raise RuntimeError("KONG_PROXY_REQUEST_COUNT must be at least 1")

    for request_index in range(1, KONG_PROXY_REQUEST_COUNT + 1):
        query = urlencode(
            {
                "source": "TP_LOCAL_STACK_VERIFICATION_V001",
                "request_index": request_index,
            },
        )
        try:
            status, body = http_get(
                f"{KONG_PROXY_URL}/get?{query}",
                headers={"Host": KONG_HOST_HEADER},
            )
            assert_status("Kong proxy /get", status, 200, body)
            validate_kong_proxy_response(body, request_index)
        except RuntimeError:
            pod_name = get_ready_pod_name("app=prometheus")
            body = kubectl_exec(
                pod_name,
                [
                    "wget",
                    "-qO-",
                    "--header",
                    f"Host: {KONG_HOST_HEADER}",
                    f"http://kong.{KUBECTL_NAMESPACE}.svc.cluster.local:8000/get?{query}",
                ],
            )
            validate_kong_proxy_response(body.encode("utf-8"), request_index)

        if request_index < KONG_PROXY_REQUEST_COUNT and KONG_PROXY_REQUEST_DELAY_SECONDS > 0:
            time.sleep(KONG_PROXY_REQUEST_DELAY_SECONDS)

    print(f"[INFO] Kong Proxy requests sent: {KONG_PROXY_REQUEST_COUNT}")


def verify_prometheus() -> None:
    ready_status, ready_body = http_get(f"{PROMETHEUS_URL}/-/ready")
    assert_status("Prometheus /-/ready", ready_status, 200, ready_body)

    targets_status, targets_body = http_get(f"{PROMETHEUS_URL}/api/v1/targets")
    assert_status("Prometheus /api/v1/targets", targets_status, 200, targets_body)
    payload = json.loads(targets_body.decode("utf-8"))
    active_targets = payload.get("data", {}).get("activeTargets", [])

    for target in active_targets:
        labels = target.get("labels", {})
        if labels.get("job") == PROMETHEUS_TARGET_JOB and target.get("health") == "up":
            return

    matching_targets = [
        target
        for target in active_targets
        if target.get("labels", {}).get("job") == PROMETHEUS_TARGET_JOB
    ]
    if matching_targets:
        details = [
            {
                "scrapeUrl": target.get("scrapeUrl"),
                "health": target.get("health"),
                "lastError": target.get("lastError"),
            }
            for target in matching_targets
        ]
        raise RuntimeError(
            f"Prometheus target '{PROMETHEUS_TARGET_JOB}' was not healthy: {json.dumps(details)}",
        )

    raise RuntimeError(f"Prometheus target '{PROMETHEUS_TARGET_JOB}' was not healthy")


def verify_grafana() -> None:
    status, body = http_get(f"{GRAFANA_URL}/api/health")
    assert_status("Grafana /api/health", status, 200, body)
    payload = json.loads(body.decode("utf-8"))
    if payload.get("database") != "ok":
        raise RuntimeError("Grafana health response did not report database=ok")


def main() -> None:
    atexit.register(cleanup_port_forwards)
    ensure_local_access()

    checks = [
        ("Kong Admin", verify_kong_admin),
        ("Kong Proxy", verify_kong_proxy),
        ("Prometheus", verify_prometheus),
        ("Grafana", verify_grafana),
    ]

    for name, check in checks:
        check()
        print(f"[PASS] {name}")

    print("[PASS] Stack verification completed")


if __name__ == "__main__":
    main()
