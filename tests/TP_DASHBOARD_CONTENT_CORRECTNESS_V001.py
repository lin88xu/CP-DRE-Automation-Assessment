#!/usr/bin/env python3

import base64
import json
import os
from pathlib import Path
from typing import Any, Dict, Iterable, List
from urllib.parse import quote

from TP_REMOTE_STACK_VERIFICATION_V001 import (
    AWS_TERRAFORM_OUTPUTS,
    GRAFANA_URL,
    STACK_TARGET,
    assert_status,
    build_url,
    decode_json,
    http_get,
    parse_bool,
    wait_for_check,
)

GRAFANA_USER = os.getenv("GRAFANA_USER", "admin")
GRAFANA_PASSWORD = os.getenv("GRAFANA_PASSWORD", "admin")
GRAFANA_TOKEN = os.getenv("GRAFANA_TOKEN", "").strip()
GRAFANA_DATASOURCE_UID = os.getenv("GRAFANA_DATASOURCE_UID", "").strip()
DEFAULT_GRAFANA_DATASOURCE_NAME = (
    "Amazon Managed Service for Prometheus" if STACK_TARGET == "aws" else "Prometheus"
)
GRAFANA_DATASOURCE_NAME = os.getenv("GRAFANA_DATASOURCE_NAME", DEFAULT_GRAFANA_DATASOURCE_NAME)
EXPECTED_GRAFANA_DATASOURCE_URL = os.getenv(
    "EXPECTED_GRAFANA_DATASOURCE_URL",
    AWS_TERRAFORM_OUTPUTS.get(
        "amp_prometheus_endpoint",
        "http://prometheus:9090" if STACK_TARGET != "aws" else "",
    ),
)
EXPECT_PROVISIONED_DASHBOARD = parse_bool(
    os.getenv("EXPECT_PROVISIONED_DASHBOARD", "false" if STACK_TARGET == "aws" else "true"),
)
REPO_ROOT = Path(__file__).resolve().parent.parent
SOURCE_DASHBOARD_PATH = Path(
    os.getenv(
        "SOURCE_DASHBOARD_PATH",
        str(REPO_ROOT / "promethusGrafana/grafana/dashboards/kong-overview.json"),
    ),
)


def grafana_headers() -> Dict[str, str]:
    if GRAFANA_TOKEN:
        return {"Authorization": f"Bearer {GRAFANA_TOKEN}"}
    token = base64.b64encode(f"{GRAFANA_USER}:{GRAFANA_PASSWORD}".encode("utf-8")).decode("ascii")
    return {"Authorization": f"Basic {token}"}


def grafana_get_json(path: str) -> Dict[str, Any]:
    status, body = http_get(build_url(GRAFANA_URL, path), headers=grafana_headers())
    assert_status(f"Grafana {path}", status, 200, body)
    return decode_json(body)


def load_source_dashboard() -> Dict[str, Any]:
    return json.loads(SOURCE_DASHBOARD_PATH.read_text(encoding="utf-8"))


def flatten_panels(panels: Iterable[Dict[str, Any]]) -> List[Dict[str, Any]]:
    flattened: List[Dict[str, Any]] = []
    for panel in panels:
        flattened.append(panel)
        nested_panels = panel.get("panels", [])
        if nested_panels:
            flattened.extend(flatten_panels(nested_panels))
    return flattened


def collect_panel_titles(panels: Iterable[Dict[str, Any]]) -> List[str]:
    return [panel.get("title") for panel in panels if panel.get("title")]


def collect_prometheus_expressions(panels: Iterable[Dict[str, Any]]) -> List[str]:
    expressions: List[str] = []
    for panel in panels:
        for target in panel.get("targets", []):
            expression = target.get("expr") or target.get("expression")
            if expression:
                expressions.append(expression)
    return expressions


def find_datasource_by_name(datasource_name: str) -> Dict[str, Any]:
    payload = grafana_get_json("/api/datasources")
    for datasource in payload:
        if datasource.get("name") == datasource_name:
            return datasource
    raise RuntimeError(f"Grafana datasource {datasource_name} was not found")


def verify_datasource(source_dashboard: Dict[str, Any]) -> None:
    payload = (
        grafana_get_json(f"/api/datasources/uid/{quote(GRAFANA_DATASOURCE_UID, safe='')}")
        if GRAFANA_DATASOURCE_UID
        else find_datasource_by_name(GRAFANA_DATASOURCE_NAME)
    )

    if GRAFANA_DATASOURCE_UID and payload.get("uid") != GRAFANA_DATASOURCE_UID:
        raise RuntimeError(f"unexpected datasource uid: {payload.get('uid')}")
    if payload.get("name") != GRAFANA_DATASOURCE_NAME:
        raise RuntimeError(f"unexpected datasource name: {payload.get('name')}")
    if payload.get("type") != "prometheus":
        raise RuntimeError(f"unexpected datasource type: {payload.get('type')}")
    if EXPECTED_GRAFANA_DATASOURCE_URL and payload.get("url") != EXPECTED_GRAFANA_DATASOURCE_URL:
        raise RuntimeError(f"unexpected datasource url: {payload.get('url')}")
    if not payload.get("isDefault"):
        raise RuntimeError("Prometheus datasource was not marked as default")


def verify_dashboard_search(source_dashboard: Dict[str, Any]) -> None:
    dashboard_uid = source_dashboard.get("uid")
    dashboard_title = source_dashboard.get("title")
    payload = grafana_get_json(f"/api/search?query={quote(dashboard_title, safe='')}")
    for item in payload:
        if item.get("uid") == dashboard_uid and item.get("title") == dashboard_title:
            return
    raise RuntimeError(f"dashboard {dashboard_title} ({dashboard_uid}) was not found in Grafana search")


def verify_dashboard_content(source_dashboard: Dict[str, Any]) -> None:
    dashboard_uid = source_dashboard.get("uid")
    dashboard_title = source_dashboard.get("title")
    payload = grafana_get_json(f"/api/dashboards/uid/{quote(dashboard_uid, safe='')}")

    meta = payload.get("meta", {})
    live_dashboard = payload.get("dashboard", {})

    if EXPECT_PROVISIONED_DASHBOARD:
        if not meta.get("provisioned"):
            raise RuntimeError("dashboard was expected to be provisioned")
        if meta.get("provisionedExternalId") != SOURCE_DASHBOARD_PATH.name:
            raise RuntimeError(f"unexpected provisionedExternalId: {meta.get('provisionedExternalId')}")
    if live_dashboard.get("uid") != dashboard_uid:
        raise RuntimeError(f"unexpected dashboard uid: {live_dashboard.get('uid')}")
    if live_dashboard.get("title") != dashboard_title:
        raise RuntimeError(f"unexpected dashboard title: {live_dashboard.get('title')}")

    source_panels = flatten_panels(source_dashboard.get("panels", []))
    live_panels = flatten_panels(live_dashboard.get("panels", []))

    if len(live_panels) != len(source_panels):
        raise RuntimeError(
            f"unexpected panel count: live={len(live_panels)} source={len(source_panels)}",
        )

    source_titles = collect_panel_titles(source_panels)
    live_titles = collect_panel_titles(live_panels)
    for title in source_titles:
        if title not in live_titles:
            raise RuntimeError(f"missing dashboard panel: {title}")

    source_expressions = collect_prometheus_expressions(source_panels)
    live_expressions = collect_prometheus_expressions(live_panels)
    for expression in source_expressions:
        if expression not in live_expressions:
            raise RuntimeError(f"missing expected Prometheus expression: {expression}")


def main() -> None:
    if not GRAFANA_URL:
        raise RuntimeError(
            "GRAFANA_URL is not configured. Set it explicitly or make terraform output grafana_workspace_url available.",
        )

    source_dashboard = load_source_dashboard()

    checks = [
        ("Grafana Datasource", lambda: verify_datasource(source_dashboard)),
        ("Grafana Dashboard Search", lambda: verify_dashboard_search(source_dashboard)),
        ("Grafana Dashboard Content", lambda: verify_dashboard_content(source_dashboard)),
    ]

    for name, check in checks:
        wait_for_check(name, check)
        print(f"[PASS] {name}")

    print("[PASS] Dashboard content verification completed")


if __name__ == "__main__":
    main()
