#!/usr/bin/env python3

import base64
import json
import os
from pathlib import Path
from typing import Dict, Iterable, List, Optional
from urllib.parse import quote

from TP_LOCAL_STACK_VERIFICATION_V001 import (
    GRAFANA_URL,
    assert_status,
    ensure_local_access,
    http_get,
)


def env_with_fallback(primary: str, fallback: str, default: str) -> str:
    return os.getenv(primary) or os.getenv(fallback) or default


GRAFANA_DATASOURCE_UID = os.getenv("GRAFANA_DATASOURCE_UID", "prometheus")
GRAFANA_DASHBOARD_UID = os.getenv("GRAFANA_DASHBOARD_UID", "mY9p7dQmz")
GRAFANA_DASHBOARD_TITLE = os.getenv("GRAFANA_DASHBOARD_TITLE", "Kong (official)")
EXPECTED_GRAFANA_DATASOURCE_URL = os.getenv(
    "EXPECTED_GRAFANA_DATASOURCE_URL",
    "http://prometheus.kong.svc.cluster.local:9090",
)
EXPECTED_TEMPLATE_VARIABLES = [
    "service",
    "instance",
    "route",
    "upstream",
    "DS_PROMETHEUS",
]
EXPECTED_PANEL_TITLES = [
    "Total requests per second (RPS)",
    "Kong Proxy Latency across all services",
    "Total Bandwidth",
    "Nginx connection state",
]
EXPECTED_PROMETHEUS_EXPRESSIONS = [
    "sum(rate(kong_http_requests_total",
    "histogram_quantile(0.90, sum(rate(kong_kong_latency_ms_bucket",
    "sum(irate(kong_bandwidth_bytes",
    "sum(kong_nginx_connections_total",
]
REPO_ROOT = Path(__file__).resolve().parent.parent
SOURCE_DASHBOARD_PATH = REPO_ROOT / "terraform/environments/aws/templates/kong-official.json"
ANSIBLE_SECRET_DIR = REPO_ROOT / "anisible" / ".secrets"


def read_secret_file(key: str) -> Optional[str]:
    candidates = [
        ANSIBLE_SECRET_DIR / f"localhost-{key}",
        ANSIBLE_SECRET_DIR / "localhost" / key,
    ]
    for path in candidates:
        if path.is_file():
            return path.read_text(encoding="utf-8").strip()
    return None


GRAFANA_USER = env_with_fallback("GRAFANA_USER", "GRAFANA_ADMIN_USER", "grafana-admin")
GRAFANA_PASSWORD = (
    os.getenv("GRAFANA_PASSWORD")
    or os.getenv("GRAFANA_ADMIN_PASSWORD")
    or read_secret_file("grafana_admin_password")
    or "admin"
)


def grafana_headers() -> Dict[str, str]:
    token = base64.b64encode(f"{GRAFANA_USER}:{GRAFANA_PASSWORD}".encode("utf-8")).decode("ascii")
    return {"Authorization": f"Basic {token}"}


def grafana_get_json(path: str) -> Dict:
    status, body = http_get(f"{GRAFANA_URL}{path}", headers=grafana_headers())
    assert_status(f"Grafana {path}", status, 200, body)
    return json.loads(body.decode("utf-8"))


def flatten_panels(panels: Iterable[Dict]) -> List[Dict]:
    flattened: List[Dict] = []
    for panel in panels:
        flattened.append(panel)
        if panel.get("panels"):
            flattened.extend(flatten_panels(panel["panels"]))
    return flattened


def collect_panel_titles(panels: Iterable[Dict]) -> List[str]:
    return [panel.get("title") for panel in panels if panel.get("title")]


def collect_prometheus_expressions(panels: Iterable[Dict]) -> List[str]:
    expressions: List[str] = []
    for panel in panels:
        for target in panel.get("targets", []):
            expr = target.get("expr") or target.get("expression")
            if expr:
                expressions.append(expr)
    return expressions


def load_source_dashboard() -> Dict:
    return json.loads(SOURCE_DASHBOARD_PATH.read_text(encoding="utf-8"))


def verify_datasource() -> None:
    payload = grafana_get_json(f"/api/datasources/uid/{quote(GRAFANA_DATASOURCE_UID, safe='')}")
    if payload.get("uid") != GRAFANA_DATASOURCE_UID:
        raise RuntimeError(f"unexpected datasource uid: {payload.get('uid')}")
    if payload.get("name") != "Prometheus":
        raise RuntimeError(f"unexpected datasource name: {payload.get('name')}")
    if payload.get("type") != "prometheus":
        raise RuntimeError(f"unexpected datasource type: {payload.get('type')}")
    if payload.get("url") != EXPECTED_GRAFANA_DATASOURCE_URL:
        raise RuntimeError(f"unexpected datasource url: {payload.get('url')}")
    if not payload.get("isDefault"):
        raise RuntimeError("Prometheus datasource was not marked as default")
    if not payload.get("readOnly"):
        raise RuntimeError("Prometheus datasource was expected to be provisioned read-only")


def verify_dashboard_search() -> None:
    payload = grafana_get_json(f"/api/search?query={quote(GRAFANA_DASHBOARD_TITLE, safe='')}")
    for item in payload:
        if item.get("uid") == GRAFANA_DASHBOARD_UID and item.get("title") == GRAFANA_DASHBOARD_TITLE:
            return
    raise RuntimeError(f"dashboard {GRAFANA_DASHBOARD_TITLE} ({GRAFANA_DASHBOARD_UID}) was not found in Grafana search")


def verify_dashboard_content() -> None:
    source_dashboard = load_source_dashboard()
    payload = grafana_get_json(f"/api/dashboards/uid/{quote(GRAFANA_DASHBOARD_UID, safe='')}")

    meta = payload.get("meta", {})
    dashboard = payload.get("dashboard", {})

    if not meta.get("provisioned"):
        raise RuntimeError("dashboard was expected to be provisioned")
    if meta.get("provisionedExternalId") != "kong-official.json":
        raise RuntimeError(f"unexpected provisionedExternalId: {meta.get('provisionedExternalId')}")
    if dashboard.get("uid") != GRAFANA_DASHBOARD_UID:
        raise RuntimeError(f"unexpected dashboard uid: {dashboard.get('uid')}")
    if dashboard.get("title") != GRAFANA_DASHBOARD_TITLE:
        raise RuntimeError(f"unexpected dashboard title: {dashboard.get('title')}")

    live_variables = [item.get("name") for item in dashboard.get("templating", {}).get("list", [])]
    for variable in EXPECTED_TEMPLATE_VARIABLES:
        if variable not in live_variables:
            raise RuntimeError(f"missing dashboard variable: {variable}")

    live_panels = flatten_panels(dashboard.get("panels", []))
    live_panel_titles = collect_panel_titles(live_panels)
    for title in EXPECTED_PANEL_TITLES:
        if title not in live_panel_titles:
            raise RuntimeError(f"missing dashboard panel: {title}")

    live_expressions = collect_prometheus_expressions(live_panels)
    for fragment in EXPECTED_PROMETHEUS_EXPRESSIONS:
        if not any(fragment in expr for expr in live_expressions):
            raise RuntimeError(f"missing expected Prometheus expression fragment: {fragment}")

    source_panels = flatten_panels(source_dashboard.get("panels", []))
    if len(live_panels) != len(source_panels):
        raise RuntimeError(
            f"unexpected panel count: live={len(live_panels)} source={len(source_panels)}",
        )


def main() -> None:
    ensure_local_access()

    checks = [
        ("Grafana Datasource", verify_datasource),
        ("Grafana Dashboard Search", verify_dashboard_search),
        ("Grafana Dashboard Content", verify_dashboard_content),
    ]

    for name, check in checks:
        check()
        print(f"[PASS] {name}")

    print("[PASS] Dashboard content verification completed")


if __name__ == "__main__":
    main()
