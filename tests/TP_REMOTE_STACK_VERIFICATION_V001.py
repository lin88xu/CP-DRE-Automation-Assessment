#!/usr/bin/env python3

import json
import os
import subprocess
import time
from pathlib import Path
from typing import Any, Callable, Dict, Optional, Tuple
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlparse
from urllib.request import Request, urlopen

REPO_ROOT = Path(__file__).resolve().parent.parent
AWS_TERRAFORM_DIR = REPO_ROOT / "terraform/environments/aws"
DEFAULT_AWS_PROXY_URL = "http://kong-aws-alb-500175267.ap-southeast-1.elb.amazonaws.com:8000"
TERRAFORM_OUTPUT_TIMEOUT_SECONDS = float(os.getenv("TERRAFORM_OUTPUT_TIMEOUT_SECONDS", "30"))
TEST_SOURCE_MARKER = "TP_REMOTE_STACK_VERIFICATION_V001"


def parse_bool(value: str) -> bool:
    return value.strip().lower() in {"1", "true", "yes", "on"}


def load_aws_terraform_outputs() -> Dict[str, str]:
    if not parse_bool(os.getenv("LOAD_AWS_TERRAFORM_OUTPUTS", "true")):
        return {}

    if not AWS_TERRAFORM_DIR.exists():
        return {}

    try:
        result = subprocess.run(
            ["terraform", "output", "-json"],
            cwd=AWS_TERRAFORM_DIR,
            capture_output=True,
            check=False,
            text=True,
            timeout=TERRAFORM_OUTPUT_TIMEOUT_SECONDS,
        )
    except (FileNotFoundError, subprocess.SubprocessError):
        return {}

    if result.returncode != 0:
        return {}

    try:
        raw_outputs = json.loads(result.stdout)
    except json.JSONDecodeError:
        return {}

    outputs: Dict[str, str] = {}
    for name, payload in raw_outputs.items():
        value = payload.get("value")
        if value is None:
            continue
        if isinstance(value, str):
            candidate = value.strip()
            if candidate:
                outputs[name] = candidate
        else:
            outputs[name] = json.dumps(value)

    return outputs


AWS_TERRAFORM_OUTPUTS = load_aws_terraform_outputs()


def resolve_setting(env_name: str, terraform_output_name: Optional[str] = None, default: str = "") -> str:
    env_value = os.getenv(env_name, "").strip()
    if env_value:
        return env_value
    if terraform_output_name:
        return AWS_TERRAFORM_OUTPUTS.get(terraform_output_name, default)
    return default


def detect_stack_target() -> str:
    if "amazonaws.com" in KONG_PROXY_URL or AWS_TERRAFORM_OUTPUTS:
        return "aws"
    return "local"


KONG_PROXY_URL = resolve_setting("KONG_PROXY_URL", "proxy_url", DEFAULT_AWS_PROXY_URL)
KONG_ADMIN_URL = resolve_setting("KONG_ADMIN_URL", "admin_url")
PROMETHEUS_URL = resolve_setting("PROMETHEUS_URL")
GRAFANA_URL = resolve_setting("GRAFANA_URL", "grafana_workspace_url")
KONG_HOST_HEADER = os.getenv("KONG_HOST_HEADER", "example.com")
STACK_TARGET = os.getenv("STACK_TARGET", detect_stack_target()).strip().lower()
REQUEST_TIMEOUT_SECONDS = float(os.getenv("REQUEST_TIMEOUT_SECONDS", "10"))
READINESS_TIMEOUT_SECONDS = float(os.getenv("READINESS_TIMEOUT_SECONDS", "180"))
RETRY_INTERVAL_SECONDS = float(os.getenv("RETRY_INTERVAL_SECONDS", "2"))
KONG_PROXY_REQUEST_COUNT = int(os.getenv("KONG_PROXY_REQUEST_COUNT", "10"))


def build_url(base_url: str, path: str, query: Optional[Dict[str, Any]] = None) -> str:
    parsed = urlparse(base_url)
    base_path = parsed.path.rstrip("/")
    suffix = path if path.startswith("/") else f"/{path}"
    full_path = f"{base_path}{suffix}" if base_path else suffix
    if query:
        return f"{parsed.scheme}://{parsed.netloc}{full_path}?{urlencode(query)}"
    return f"{parsed.scheme}://{parsed.netloc}{full_path}"


def http_get(url: str, headers: Optional[Dict[str, str]] = None) -> Tuple[int, bytes]:
    request = Request(url, headers=headers or {}, method="GET")
    try:
        with urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
            return response.getcode(), response.read()
    except HTTPError as exc:
        return exc.code, exc.read()
    except URLError as exc:
        raise RuntimeError(f"request failed for {url}: {exc}") from exc


def decode_json(body: bytes) -> Dict[str, Any]:
    try:
        return json.loads(body.decode("utf-8"))
    except json.JSONDecodeError as exc:
        snippet = body.decode("utf-8", errors="replace")[:300]
        raise RuntimeError(f"response was not valid JSON: {snippet}") from exc


def assert_status(name: str, status: int, expected: int, body: bytes) -> None:
    if status != expected:
        snippet = body.decode("utf-8", errors="replace")[:300]
        raise RuntimeError(f"{name} returned {status}, expected {expected}: {snippet}")


def wait_for_check(name: str, check: Callable[[], None]) -> None:
    deadline = time.time() + READINESS_TIMEOUT_SECONDS
    last_error = None
    next_progress_at = time.time()

    print(f"[RUN] {name}")

    while time.time() < deadline:
        try:
            check()
            return
        except Exception as exc:  # noqa: BLE001
            last_error = exc
            now = time.time()
            if now >= next_progress_at:
                remaining_seconds = max(0, int(deadline - now))
                print(f"[WAIT] {name}: {exc} ({remaining_seconds}s remaining)")
                next_progress_at = now + 10
            time.sleep(RETRY_INTERVAL_SECONDS)

    raise RuntimeError(f"{name} did not become ready: {last_error}") from last_error


def emit_skip(name: str, reason: str) -> None:
    print(f"[SKIP] {name}: {reason}")


def verify_kong_admin() -> None:
    status, body = http_get(build_url(KONG_ADMIN_URL, "/status"))
    assert_status("Kong Admin /status", status, 200, body)
    payload = decode_json(body)
    if "database" not in payload:
        raise RuntimeError("Kong Admin /status response did not include database state")


def verify_kong_proxy() -> None:
    for request_index in range(1, KONG_PROXY_REQUEST_COUNT + 1):
        status, body = http_get(
            build_url(
                KONG_PROXY_URL,
                "/get",
                {
                    "source": TEST_SOURCE_MARKER,
                    "request_index": request_index,
                },
            ),
            headers={"Host": KONG_HOST_HEADER},
        )
        assert_status("Kong proxy request", status, 200, body)
        payload = decode_json(body)
        args = payload.get("args", {})
        if args.get("source") != TEST_SOURCE_MARKER:
            raise RuntimeError("Kong proxy response did not include the expected source marker")
        if args.get("request_index") != str(request_index):
            raise RuntimeError(
                f"Kong proxy response did not include request_index={request_index}",
            )


def main() -> None:
    checks = [("Kong Proxy", verify_kong_proxy)]

    if KONG_ADMIN_URL:
        checks.append(("Kong Admin", verify_kong_admin))
    else:
        emit_skip(
            "Kong Admin",
            "Admin API check skipped: AWS keeps the Admin API unpublished by default unless publish_admin_api is enabled",
        )

    emit_skip(
        "Prometheus Targets",
        "Prometheus target validation is intentionally skipped in remote stack verification",
    )

    emit_skip("Grafana Health", "Grafana health check is intentionally skipped in remote stack verification")

    for name, check in checks:
        wait_for_check(name, check)
        print(f"[PASS] {name}")

    print(f"[PASS] {STACK_TARGET.upper()} stack verification completed")


if __name__ == "__main__":
    main()
