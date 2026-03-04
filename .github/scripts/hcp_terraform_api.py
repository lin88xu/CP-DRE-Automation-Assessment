#!/usr/bin/env python3

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


def api_base() -> str:
    host = os.environ.get("TFC_HOST", "app.terraform.io").strip().rstrip("/")
    if host.startswith("http://") or host.startswith("https://"):
        return f"{host}/api/v2"
    return f"https://{host}/api/v2"


def token() -> str:
    value = os.environ.get("TFC_TOKEN", "").strip()
    if not value:
        raise SystemExit("TFC_TOKEN is required")
    return value


def request_json(method: str, path: str, payload: dict | None = None) -> dict:
    body = None
    if payload is not None:
        body = json.dumps(payload).encode("utf-8")

    request = urllib.request.Request(
        f"{api_base()}{path}",
        data=body,
        method=method,
        headers={
            "Authorization": f"Bearer {token()}",
            "Content-Type": "application/vnd.api+json",
        },
    )

    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            raw = response.read().decode("utf-8")
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        error_body = exc.read().decode("utf-8", errors="replace")
        raise SystemExit(f"{method} {path} failed: {exc.code} {error_body}") from exc


def upload_archive(upload_url: str, archive_path: str) -> None:
    with open(archive_path, "rb") as handle:
        request = urllib.request.Request(
            upload_url,
            data=handle.read(),
            method="PUT",
            headers={"Content-Type": "application/octet-stream"},
        )
    try:
        with urllib.request.urlopen(request, timeout=300):
            return
    except urllib.error.HTTPError as exc:
        error_body = exc.read().decode("utf-8", errors="replace")
        raise SystemExit(f"PUT upload failed: {exc.code} {error_body}") from exc


def run_url(organization: str, workspace: str, run_id: str) -> str:
    host = os.environ.get("TFC_HOST", "app.terraform.io").strip().rstrip("/")
    if host.startswith("http://"):
        host = host[len("http://") :]
    if host.startswith("https://"):
        host = host[len("https://") :]
    return f"https://{host}/app/{organization}/{workspace}/runs/{run_id}"


def workspace_info(args: argparse.Namespace) -> None:
    data = request_json("GET", f"/organizations/{args.organization}/workspaces/{args.workspace}")
    attrs = data["data"]["attributes"]
    info = {
        "id": data["data"]["id"],
        "name": data["data"]["attributes"]["name"],
        "organization": args.organization,
        "execution_mode": attrs.get("execution-mode"),
        "operations": attrs.get("operations"),
    }
    print(json.dumps(info))


def create_config_version(args: argparse.Namespace) -> None:
    payload = {
        "data": {
            "type": "configuration-versions",
            "attributes": {
                "auto-queue-runs": False,
                "provisional": bool(args.provisional),
            },
        }
    }
    data = request_json("POST", f"/workspaces/{args.workspace_id}/configuration-versions", payload)
    result = {
        "id": data["data"]["id"],
        "status": data["data"]["attributes"].get("status"),
        "upload_url": data["data"]["attributes"]["upload-url"],
    }
    print(json.dumps(result))


def create_run(args: argparse.Namespace) -> None:
    attributes = {
        "message": args.message,
        "plan-only": bool(args.plan_only),
        "auto-apply": bool(args.auto_apply),
    }
    payload = {
        "data": {
            "type": "runs",
            "attributes": attributes,
            "relationships": {
                "workspace": {"data": {"type": "workspaces", "id": args.workspace_id}},
                "configuration-version": {
                    "data": {"type": "configuration-versions", "id": args.config_version_id}
                },
            },
        }
    }
    data = request_json("POST", "/runs", payload)
    result = {
        "id": data["data"]["id"],
        "status": data["data"]["attributes"]["status"],
        "workspace_id": args.workspace_id,
        "config_version_id": args.config_version_id,
    }
    print(json.dumps(result))


def apply_run(args: argparse.Namespace) -> None:
    request_json("POST", f"/runs/{args.run_id}/actions/apply", {"comment": "Applied by GitHub Actions"})
    print(json.dumps({"id": args.run_id, "applied": True}))


def wait_run(args: argparse.Namespace) -> None:
    success_states = {value.strip() for value in args.success_status.split(",") if value.strip()}
    failure_states = {"errored", "canceled", "force_canceled", "discarded", "apply_errored", "policy_soft_failed"}
    deadline = time.time() + args.timeout
    last = None

    while time.time() < deadline:
        data = request_json("GET", f"/runs/{args.run_id}")
        run = data["data"]
        attrs = run["attributes"]
        status = attrs["status"]
        actions = attrs.get("actions", {})
        confirmable = bool(actions.get("is-confirmable"))
        result = {
            "id": run["id"],
            "status": status,
            "confirmable": confirmable,
            "has_changes": attrs.get("has-changes"),
            "workspace_id": run.get("relationships", {}).get("workspace", {}).get("data", {}).get("id"),
        }
        last = result

        if status in success_states:
            result["result"] = "success"
            print(json.dumps(result))
            return

        if args.allow_confirmable and confirmable:
            result["result"] = "confirmable"
            print(json.dumps(result))
            return

        if status in failure_states:
            result["result"] = "failed"
            print(json.dumps(result))
            raise SystemExit(f"Run {args.run_id} ended in failure state: {status}")

        time.sleep(args.poll_interval)

    if last is not None:
        print(json.dumps(last))
    raise SystemExit(f"Timed out waiting for run {args.run_id}")


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    workspace = subparsers.add_parser("workspace-info")
    workspace.add_argument("--organization", required=True)
    workspace.add_argument("--workspace", required=True)
    workspace.set_defaults(func=workspace_info)

    config = subparsers.add_parser("create-config-version")
    config.add_argument("--workspace-id", required=True)
    config.add_argument("--provisional", action="store_true")
    config.set_defaults(func=create_config_version)

    upload = subparsers.add_parser("upload-config")
    upload.add_argument("--upload-url", required=True)
    upload.add_argument("--archive", required=True)
    upload.set_defaults(func=lambda args: upload_archive(args.upload_url, args.archive))

    create = subparsers.add_parser("create-run")
    create.add_argument("--workspace-id", required=True)
    create.add_argument("--config-version-id", required=True)
    create.add_argument("--message", required=True)
    create.add_argument("--plan-only", action="store_true")
    create.add_argument("--auto-apply", action="store_true")
    create.set_defaults(func=create_run)

    wait = subparsers.add_parser("wait-run")
    wait.add_argument("--run-id", required=True)
    wait.add_argument("--success-status", required=True)
    wait.add_argument("--timeout", type=int, default=1800)
    wait.add_argument("--poll-interval", type=int, default=10)
    wait.add_argument("--allow-confirmable", action="store_true")
    wait.set_defaults(func=wait_run)

    apply_cmd = subparsers.add_parser("apply-run")
    apply_cmd.add_argument("--run-id", required=True)
    apply_cmd.set_defaults(func=apply_run)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
