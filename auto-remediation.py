#!/usr/bin/env python3

import argparse
import json
import os
import socket
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional
from urllib.error import URLError
from urllib.request import urlopen

ROOT_DIR = Path(__file__).resolve().parent
LOCAL_RUNTIME_SCRIPT = ROOT_DIR / "local-runtime.sh"
PERSISTENT_DATA_SCRIPT = ROOT_DIR / "persistent-data.sh"
DISASTER_RECOVERY_SCRIPT = ROOT_DIR / "terraform" / "disaster-recovery.sh"
AUTO_REMEDIATION_STATE_DIR = Path(
    os.getenv("AUTO_REMEDIATION_STATE_DIR_OVERRIDE", ROOT_DIR / ".auto-remediation"),
)
BACKUP_ROOT = ROOT_DIR / ".backups"
DEFAULT_PORTS = {
    "grafana": 3000,
    "prometheus": 9090,
    "kong_proxy": 8000,
    "kong_admin": 8001,
    "kong_manager": 8002,
}


def utc_timestamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def log(message: str) -> None:
    print(f"[auto-remediation] {message}")


def is_port_open(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(0.5)
        return sock.connect_ex(("127.0.0.1", port)) == 0


def ensure_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


def write_text(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")


def write_json(path: Path, payload: Dict[str, Any]) -> None:
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def command_to_string(command: List[str]) -> str:
    return " ".join(command)


def run_command(
    command: List[str],
    log_path: Path,
    *,
    cwd: Optional[Path] = None,
    check: bool = False,
) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        command,
        cwd=str(cwd or ROOT_DIR),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    write_text(
        log_path,
        f"$ {command_to_string(command)}\n\n"
        f"exit_code={result.returncode}\n\n"
        f"--- stdout ---\n{result.stdout}\n"
        f"--- stderr ---\n{result.stderr}\n",
    )
    if check and result.returncode != 0:
        raise RuntimeError(f"command failed ({result.returncode}): {command_to_string(command)}")
    return result


def best_effort_run(command: List[str], log_path: Path) -> Dict[str, Any]:
    try:
        result = run_command(command, log_path)
        return {
            "command": command,
            "exit_code": result.returncode,
            "log_path": str(log_path),
        }
    except Exception as exc:  # pragma: no cover - defensive logging
        write_text(log_path, f"$ {command_to_string(command)}\n\nerror={exc}\n")
        return {
            "command": command,
            "exit_code": -1,
            "error": str(exc),
            "log_path": str(log_path),
        }


def become_args(args: argparse.Namespace) -> List[str]:
    if args.ask_become_pass:
        return ["--ask-become-pass"]
    if args.no_ask_become_pass:
        return ["--no-ask-become-pass"]
    return []


def local_runtime_command(
    args: argparse.Namespace,
    action: str,
    *,
    skip_terraform: bool = False,
    verify: bool = False,
    auto_rollback: bool = False,
) -> List[str]:
    command = ["bash", str(LOCAL_RUNTIME_SCRIPT), action]
    command.extend(become_args(args))
    if skip_terraform and action == "up":
        command.append("--skip-terraform")
    if verify and action == "up":
        command.append("--verify")
    if auto_rollback and action == "up":
        command.append("--auto-rollback")
    return command


def persistent_data_command(action: str, *extra: str) -> List[str]:
    return ["bash", str(PERSISTENT_DATA_SCRIPT), action, "local-minikube", *extra]


def disaster_recovery_command(args: argparse.Namespace) -> List[str]:
    command = ["bash", str(DISASTER_RECOVERY_SCRIPT), "local", "rebuild"]
    command.extend(become_args(args))
    return command


def parse_runtime_active(status_output: str) -> bool:
    for line in status_output.splitlines():
        if line.startswith("Local runtime status:"):
            return line.split(":", 1)[1].strip() == "local"
    return False


def find_latest_local_backup() -> Optional[Path]:
    candidates = sorted(
        BACKUP_ROOT.glob("local-minikube-*"),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )
    return candidates[0] if candidates else None


def collect_prometheus_alerts(log_path: Path) -> Dict[str, Any]:
    url = "http://127.0.0.1:9090/api/v1/alerts"
    if not is_port_open(DEFAULT_PORTS["prometheus"]):
        write_text(log_path, "Prometheus is not reachable on localhost:9090\n")
        return {"reachable": False, "alerts": [], "log_path": str(log_path)}

    try:
        with urlopen(url, timeout=5) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except (URLError, OSError, TimeoutError, json.JSONDecodeError) as exc:
        write_text(log_path, f"Failed to query {url}: {exc}\n")
        return {
            "reachable": False,
            "alerts": [],
            "error": str(exc),
            "log_path": str(log_path),
        }

    alerts = payload.get("data", {}).get("alerts", [])
    write_json(log_path, payload)
    return {
        "reachable": True,
        "alerts": alerts,
        "firing": [alert for alert in alerts if alert.get("state") == "firing"],
        "log_path": str(log_path),
    }


def capture_cluster_evidence(run_dir: Path) -> Dict[str, Any]:
    evidence: Dict[str, Any] = {}
    if not shutil_which("kubectl"):
        return evidence

    evidence["pods"] = best_effort_run(
        ["kubectl", "-n", "kong", "get", "pods,svc,hpa,pvc"],
        run_dir / "kubectl-pods-svc-hpa-pvc.log",
    )
    evidence["events"] = best_effort_run(
        ["kubectl", "-n", "kong", "get", "events", "--sort-by=.metadata.creationTimestamp"],
        run_dir / "kubectl-events.log",
    )
    return evidence


def shutil_which(command: str) -> Optional[str]:
    for directory in os.getenv("PATH", "").split(os.pathsep):
        candidate = Path(directory) / command
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None


def run_health_script(run_dir: Path, name: str, script_name: str) -> Dict[str, Any]:
    log_path = run_dir / f"{name}.log"
    result = run_command(["python3", str(ROOT_DIR / "tests" / script_name)], log_path)
    return {
        "name": name,
        "script": script_name,
        "passed": result.returncode == 0,
        "exit_code": result.returncode,
        "log_path": str(log_path),
    }


def detect_health(args: argparse.Namespace, run_dir: Path) -> Dict[str, Any]:
    ensure_dir(run_dir)
    report: Dict[str, Any] = {
        "checked_at": utc_now_iso(),
        "run_dir": str(run_dir),
        "healthy": False,
        "scenario": "unknown",
        "reason": "",
    }

    status_result = run_command(
        ["bash", str(LOCAL_RUNTIME_SCRIPT), "status", "--no-ask-become-pass"],
        run_dir / "local-runtime-status.log",
    )
    runtime_active = parse_runtime_active(status_result.stdout)
    report["runtime_active"] = runtime_active
    report["status_log"] = str(run_dir / "local-runtime-status.log")
    report["status_exit_code"] = status_result.returncode

    if not runtime_active:
        report["scenario"] = "runtime_off"
        report["reason"] = "The local runtime is not active."
        write_json(run_dir / "summary.json", report)
        return report

    ports = {name: is_port_open(port) for name, port in DEFAULT_PORTS.items()}
    missing_ports = [name for name, open_ in ports.items() if not open_]
    report["ports"] = ports
    report["missing_ports"] = missing_ports
    report["evidence"] = capture_cluster_evidence(run_dir)

    if missing_ports:
        report["scenario"] = "ports_missing"
        report["reason"] = f"Local port-forwards are missing for: {', '.join(missing_ports)}."
        report["prometheus_alerts"] = collect_prometheus_alerts(run_dir / "prometheus-alerts.json")
        write_json(run_dir / "summary.json", report)
        return report

    local_verification = run_health_script(
        run_dir,
        "local-stack-verification",
        "TP_LOCAL_STACK_VERIFICATION_V001.py",
    )
    report["local_verification"] = local_verification
    if not local_verification["passed"]:
        report["scenario"] = "service_health_failed"
        report["reason"] = "Core local stack verification failed."
        report["prometheus_alerts"] = collect_prometheus_alerts(run_dir / "prometheus-alerts.json")
        write_json(run_dir / "summary.json", report)
        return report

    if not args.skip_dashboard_check:
        dashboard_verification = run_health_script(
            run_dir,
            "dashboard-content-verification",
            "TP_DASHBOARD_CONTENT_CORRECTNESS_V001.py",
        )
        report["dashboard_verification"] = dashboard_verification
        if not dashboard_verification["passed"]:
            report["scenario"] = "dashboard_content_failed"
            report["reason"] = "Grafana dashboard verification failed."
            report["prometheus_alerts"] = collect_prometheus_alerts(run_dir / "prometheus-alerts.json")
            write_json(run_dir / "summary.json", report)
            return report

    if args.include_hpa_check:
        hpa_verification = run_health_script(
            run_dir,
            "hpa-verification",
            "TP_HPA_SCALING_UNDER_LOAD_V001.py",
        )
        report["hpa_verification"] = hpa_verification
        if not hpa_verification["passed"]:
            report["scenario"] = "hpa_scale_failed"
            report["reason"] = "HPA scale verification failed."
            report["prometheus_alerts"] = collect_prometheus_alerts(run_dir / "prometheus-alerts.json")
            write_json(run_dir / "summary.json", report)
            return report

    report["prometheus_alerts"] = collect_prometheus_alerts(run_dir / "prometheus-alerts.json")
    report["healthy"] = True
    report["scenario"] = "healthy"
    report["reason"] = "All enabled health checks passed."
    write_json(run_dir / "summary.json", report)
    return report


def maybe_create_protective_backup(
    args: argparse.Namespace,
    run_dir: Path,
    actions: List[Dict[str, Any]],
) -> Optional[str]:
    if not args.backup_before_destructive:
        return None

    before = {path.resolve() for path in BACKUP_ROOT.glob("local-minikube-*")}
    action_log = run_dir / f"{len(actions) + 1:02d}-protective-backup.log"
    result = run_command(
        persistent_data_command("backup", "--output-dir", str(BACKUP_ROOT)),
        action_log,
    )
    action_record = {
        "type": "protective_backup",
        "command": persistent_data_command("backup", "--output-dir", str(BACKUP_ROOT)),
        "exit_code": result.returncode,
        "log_path": str(action_log),
    }
    after = {path.resolve() for path in BACKUP_ROOT.glob("local-minikube-*")}
    new_backups = sorted(after - before)
    if new_backups:
        action_record["backup_dir"] = str(new_backups[-1])
    actions.append(action_record)
    if result.returncode != 0:
        return None
    return action_record.get("backup_dir")


def execute_action(
    run_dir: Path,
    actions: List[Dict[str, Any]],
    action_type: str,
    command: List[str],
) -> Dict[str, Any]:
    log_path = run_dir / f"{len(actions) + 1:02d}-{action_type}.log"
    result = run_command(command, log_path)
    record = {
        "type": action_type,
        "command": command,
        "exit_code": result.returncode,
        "log_path": str(log_path),
    }
    actions.append(record)
    return record


def remediate_once(args: argparse.Namespace, run_dir: Path) -> int:
    ensure_dir(run_dir)
    detections: List[Dict[str, Any]] = []
    actions: List[Dict[str, Any]] = []
    summary: Dict[str, Any] = {
        "started_at": utc_now_iso(),
        "run_dir": str(run_dir),
        "mode": "remediate",
    }

    initial_report = detect_health(args, run_dir / "detect-initial")
    detections.append(initial_report)
    if initial_report["healthy"]:
        summary["detections"] = detections
        summary["actions"] = actions
        summary["result"] = "healthy"
        write_json(run_dir / "summary.json", summary)
        log(f"Local runtime is healthy. Evidence written to {run_dir}")
        return 0

    safe_redeploy = local_runtime_command(
        args,
        "up",
        skip_terraform=initial_report["scenario"] != "runtime_off",
        verify=True,
        auto_rollback=True,
    )
    execute_action(run_dir, actions, "safe-redeploy", safe_redeploy)

    post_redeploy = detect_health(args, run_dir / "detect-post-safe-redeploy")
    detections.append(post_redeploy)
    if post_redeploy["healthy"]:
        summary["detections"] = detections
        summary["actions"] = actions
        summary["result"] = "recovered_after_safe_redeploy"
        write_json(run_dir / "summary.json", summary)
        log(f"Recovered the local runtime with a safe redeploy. Evidence written to {run_dir}")
        return 0

    protective_backup_dir = None

    if args.allow_restore:
        latest_backup = find_latest_local_backup()
        if latest_backup is None:
            actions.append(
                {
                    "type": "restore_latest_backup",
                    "skipped": True,
                    "reason": "No local-minikube backup was found under .backups/",
                },
            )
        else:
            protective_backup_dir = maybe_create_protective_backup(args, run_dir, actions)
            restore_result = execute_action(
                run_dir,
                actions,
                "restore-latest-backup",
                persistent_data_command("restore", "--input-dir", str(latest_backup)),
            )
            if restore_result["exit_code"] == 0:
                execute_action(
                    run_dir,
                    actions,
                    "post-restore-refresh",
                    local_runtime_command(
                        args,
                        "up",
                        skip_terraform=True,
                        verify=True,
                        auto_rollback=True,
                    ),
                )
                post_restore = detect_health(args, run_dir / "detect-post-restore")
                detections.append(post_restore)
                if post_restore["healthy"]:
                    summary["detections"] = detections
                    summary["actions"] = actions
                    summary["result"] = "recovered_after_restore"
                    summary["restored_from"] = str(latest_backup)
                    if protective_backup_dir:
                        summary["protective_backup_dir"] = protective_backup_dir
                    write_json(run_dir / "summary.json", summary)
                    log(f"Recovered the local runtime from backup {latest_backup}. Evidence written to {run_dir}")
                    return 0

    if args.allow_disaster_recovery:
        if protective_backup_dir is None:
            protective_backup_dir = maybe_create_protective_backup(args, run_dir, actions)
        execute_action(
            run_dir,
            actions,
            "local-disaster-recovery",
            disaster_recovery_command(args),
        )
        post_rebuild = detect_health(args, run_dir / "detect-post-disaster-recovery")
        detections.append(post_rebuild)
        if post_rebuild["healthy"]:
            summary["detections"] = detections
            summary["actions"] = actions
            summary["result"] = "recovered_after_disaster_recovery"
            if protective_backup_dir:
                summary["protective_backup_dir"] = protective_backup_dir
            write_json(run_dir / "summary.json", summary)
            log(f"Recovered the local runtime with disaster recovery rebuild. Evidence written to {run_dir}")
            return 0

    summary["detections"] = detections
    summary["actions"] = actions
    summary["result"] = "recovery_failed"
    if protective_backup_dir:
        summary["protective_backup_dir"] = protective_backup_dir
    write_json(run_dir / "summary.json", summary)
    log(f"Automatic remediation did not restore the local runtime. Evidence written to {run_dir}")
    return 1


def detect_once(args: argparse.Namespace, run_dir: Path) -> int:
    report = detect_health(args, run_dir)
    if report["healthy"]:
        log(f"Detection completed: healthy. Evidence written to {run_dir}")
        return 0
    log(f"Detection completed: {report['scenario']}. Evidence written to {run_dir}")
    return 1


def watch_loop(args: argparse.Namespace, run_dir: Path) -> int:
    iterations = 0
    while args.max_iterations == 0 or iterations < args.max_iterations:
        iterations += 1
        cycle_dir = ensure_dir(run_dir / f"cycle-{iterations:03d}")
        log(f"Starting watch cycle {iterations}")
        exit_code = remediate_once(args, cycle_dir)
        if exit_code == 0:
            time.sleep(args.interval_seconds)
            continue
        if args.stop_on_failure:
            return exit_code
        time.sleep(args.interval_seconds)
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Automate local failure detection and guarded recovery for the Minikube-backed stack.",
    )
    parser.add_argument(
        "action",
        choices=["detect", "remediate", "watch"],
        nargs="?",
        default="detect",
        help="Run passive detection, one remediation cycle, or repeated remediation cycles.",
    )
    parser.add_argument(
        "--skip-dashboard-check",
        action="store_true",
        help="Skip the Grafana dashboard-content verification check.",
    )
    parser.add_argument(
        "--include-hpa-check",
        action="store_true",
        help="Include the HPA load test in detection and remediation health checks.",
    )
    parser.add_argument(
        "--allow-restore",
        action="store_true",
        help="Allow restoring the most recent local-minikube backup if safe redeploy does not fix the stack.",
    )
    parser.add_argument(
        "--allow-disaster-recovery",
        action="store_true",
        help="Allow a full local disaster-recovery rebuild if earlier remediation steps fail.",
    )
    parser.add_argument(
        "--backup-before-destructive",
        action="store_true",
        help="Create a protective local-minikube backup before restore or disaster-recovery actions.",
    )
    parser.add_argument(
        "--interval-seconds",
        type=float,
        default=300.0,
        help="Polling interval for watch mode. Default: 300 seconds.",
    )
    parser.add_argument(
        "--max-iterations",
        type=int,
        default=0,
        help="Maximum watch iterations. Default: 0 for unlimited.",
    )
    parser.add_argument(
        "--stop-on-failure",
        action="store_true",
        help="Stop watch mode immediately if a remediation cycle still ends unhealthy.",
    )
    parser.add_argument(
        "--ask-become-pass",
        action="store_true",
        help="Always pass -K through to local-runtime.sh and disaster-recovery.sh.",
    )
    parser.add_argument(
        "--no-ask-become-pass",
        action="store_true",
        help="Never pass -K through to local-runtime.sh and disaster-recovery.sh.",
    )
    return parser.parse_args()


def validate_args(args: argparse.Namespace) -> None:
    if args.ask_become_pass and args.no_ask_become_pass:
        raise SystemExit("Choose only one of --ask-become-pass or --no-ask-become-pass.")


def main() -> int:
    args = parse_args()
    validate_args(args)

    run_root = ensure_dir(AUTO_REMEDIATION_STATE_DIR / args.action / utc_timestamp())

    if args.action == "detect":
        return detect_once(args, run_root)
    if args.action == "remediate":
        return remediate_once(args, run_root)
    return watch_loop(args, run_root)


if __name__ == "__main__":
    sys.exit(main())
