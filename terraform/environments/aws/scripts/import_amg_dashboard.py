#!/usr/bin/env python3

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request


def require_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"missing required environment variable: {name}")
    return value


def normalize_base_url(url: str) -> str:
    candidate = url.strip()
    if not urllib.parse.urlparse(candidate).scheme:
        candidate = f"https://{candidate}"
    return candidate.rstrip("/")


def grafana_request(base_url: str, token: str, method: str, path: str, payload=None):
    body = None
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
    }

    if payload is not None:
        body = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"

    request = urllib.request.Request(
        f"{base_url.rstrip('/')}{path}",
        data=body,
        headers=headers,
        method=method,
    )

    try:
        with urllib.request.urlopen(request) as response:
            raw = response.read().decode("utf-8")
            return response.getcode(), json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        raw = error.read().decode("utf-8")
        try:
            details = json.loads(raw)
        except Exception:
            details = raw
        raise RuntimeError(f"Grafana API {method} {path} failed: {error.code} {details}") from error


def normalize_amp_datasource_url(query_url: str) -> str:
    url = query_url.rstrip("/")
    for suffix in ("/api/v1/query_range", "/api/v1/query", "/api/v1"):
        if url.endswith(suffix):
            return url[: -len(suffix)]
    return url


def find_datasource(base_url: str, token: str, name: str):
    _, datasources = grafana_request(base_url, token, "GET", "/api/datasources")
    for datasource in datasources:
        if datasource.get("name") == name:
            return datasource
    return None


def upsert_datasource(base_url: str, token: str, amp_query_url: str, region: str, datasource_name: str):
    payload = {
        "name": datasource_name,
        "type": "prometheus",
        "access": "proxy",
        "url": normalize_amp_datasource_url(amp_query_url),
        "isDefault": True,
        "jsonData": {
            "httpMethod": "POST",
            "sigV4Auth": True,
            "sigV4AuthType": "default",
            "sigV4Region": region,
        },
    }

    existing = find_datasource(base_url, token, datasource_name)
    if existing:
        payload["id"] = existing["id"]
        grafana_request(base_url, token, "PUT", f"/api/datasources/{existing['id']}", payload)
        return datasource_name

    grafana_request(base_url, token, "POST", "/api/datasources", payload)
    return datasource_name


def import_dashboard(base_url: str, token: str, dashboard_path: str, datasource_name: str):
    with open(dashboard_path, "r", encoding="utf-8") as dashboard_file:
        dashboard_text = dashboard_file.read().replace("${DS_PROMETHEUS}", datasource_name)

    dashboard = json.loads(dashboard_text)
    dashboard.pop("__inputs", None)
    dashboard["id"] = None

    payload = {
        "dashboard": dashboard,
        "overwrite": True,
        "message": "Imported by Terraform",
    }

    _, response = grafana_request(base_url, token, "POST", "/api/dashboards/db", payload)
    return response.get("url", f"/d/{dashboard.get('uid', '')}")


def main():
    base_url = normalize_base_url(require_env("AMG_URL"))
    token = require_env("AMG_TOKEN")
    amp_query_url = require_env("AMP_QUERY_URL")
    region = require_env("AWS_REGION")
    dashboard_path = require_env("DASHBOARD_JSON")
    datasource_name = require_env("DATASOURCE_NAME")

    datasource_name = upsert_datasource(base_url, token, amp_query_url, region, datasource_name)
    dashboard_url = import_dashboard(base_url, token, dashboard_path, datasource_name)
    print(f"Imported dashboard to {base_url.rstrip('/')}{dashboard_url}")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
