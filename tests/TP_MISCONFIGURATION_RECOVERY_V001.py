#!/usr/bin/env python3

import os
import subprocess
import time
from pathlib import Path
from typing import Callable, List, Optional

from TP_REMOTE_STACK_VERIFICATION_V001 import (
    KONG_ADMIN_URL,
    KONG_HOST_HEADER,
    KONG_PROXY_URL,
    build_url,
    http_get,
    verify_kong_admin,
    verify_kong_proxy,
)

REPO_ROOT = Path(__file__).resolve().parent.parent
AWS_TERRAFORM_TFVARS = REPO_ROOT / "terraform/environments/aws/terraform.tfvars"
TARGET_BRANCH = os.getenv("TARGET_BRANCH", "release/aws-observability")
BAD_UPSTREAM_URL = os.getenv("BAD_UPSTREAM_URL", "http://127.0.0.1:9")
DEPLOYMENT_TIMEOUT_SECONDS = float(os.getenv("DEPLOYMENT_TIMEOUT_SECONDS", "1800"))
RETRY_INTERVAL_SECONDS = float(os.getenv("RETRY_INTERVAL_SECONDS", "10"))
MISCONFIGURATION_COMMIT_MESSAGE = os.getenv(
    "MISCONFIGURATION_COMMIT_MESSAGE",
    "demo: break sample upstream for recovery verification",
)


def run_command(args: List[str], cwd: Path = REPO_ROOT) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        args,
        cwd=cwd,
        capture_output=True,
        check=False,
        text=True,
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        raise RuntimeError(f"command failed ({' '.join(args)}): {detail}")
    return result


def git_output(args: List[str]) -> str:
    return run_command(["git", *args]).stdout.strip()


def wait_for_demo_check(name: str, timeout_seconds: float, check: Callable[[], None]) -> None:
    deadline = time.time() + timeout_seconds
    last_error: Optional[Exception] = None
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
                next_progress_at = now + 30
            time.sleep(RETRY_INTERVAL_SECONDS)

    raise RuntimeError(f"{name} did not complete successfully: {last_error}") from last_error


def ensure_clean_worktree() -> None:
    status = git_output(["status", "--porcelain"])
    if status:
        raise RuntimeError("git worktree must be clean before running the misconfiguration recovery demo")


def ensure_target_branch() -> str:
    current_branch = git_output(["rev-parse", "--abbrev-ref", "HEAD"])
    if current_branch != TARGET_BRANCH:
        print(f"[RUN] Switching Git branch from {current_branch} to {TARGET_BRANCH}")
        run_command(["git", "checkout", TARGET_BRANCH])
    return current_branch


def set_bad_upstream() -> None:
    lines = AWS_TERRAFORM_TFVARS.read_text(encoding="utf-8").splitlines()
    updated_lines: List[str] = []
    replaced = False

    for line in lines:
        if line.strip().startswith("upstream_url"):
            updated_lines.append(f'upstream_url                  = "{BAD_UPSTREAM_URL}"')
            replaced = True
        else:
            updated_lines.append(line)

    if not replaced:
        updated_lines.append(f'upstream_url                  = "{BAD_UPSTREAM_URL}"')

    AWS_TERRAFORM_TFVARS.write_text("\n".join(updated_lines) + "\n", encoding="utf-8")


def commit_and_push(message: str) -> str:
    run_command(["git", "add", str(AWS_TERRAFORM_TFVARS.relative_to(REPO_ROOT))])
    run_command(["git", "commit", "-m", message])
    commit_sha = git_output(["rev-parse", "HEAD"])
    run_command(["git", "push", "origin", TARGET_BRANCH])
    return commit_sha


def revert_and_push(commit_sha: str) -> None:
    run_command(["git", "revert", "--no-edit", commit_sha])
    run_command(["git", "push", "origin", TARGET_BRANCH])


def verify_proxy_failure() -> None:
    status, body = http_get(
        build_url(
            KONG_PROXY_URL,
            "/get",
            {
                "source": "TP_MISCONFIGURATION_RECOVERY_V001",
            },
        ),
        headers={"Host": KONG_HOST_HEADER},
    )
    if status < 500:
        snippet = body.decode("utf-8", errors="replace")[:200]
        raise RuntimeError(f"expected 5xx from misconfigured upstream, got {status}: {snippet}")


def verify_service_recovery() -> None:
    verify_kong_proxy()
    if KONG_ADMIN_URL:
        verify_kong_admin()


def restore_original_branch(original_branch: str) -> None:
    current_branch = git_output(["rev-parse", "--abbrev-ref", "HEAD"])
    if original_branch and current_branch != original_branch:
        run_command(["git", "checkout", original_branch])


def main() -> None:
    if not AWS_TERRAFORM_TFVARS.exists():
        raise RuntimeError(f"terraform tfvars file was not found: {AWS_TERRAFORM_TFVARS}")

    ensure_clean_worktree()
    original_branch = ensure_target_branch()
    bad_commit_sha = ""

    try:
        print(f"[RUN] Introducing upstream misconfiguration in {AWS_TERRAFORM_TFVARS}")
        set_bad_upstream()
        bad_commit_sha = commit_and_push(MISCONFIGURATION_COMMIT_MESSAGE)

        wait_for_demo_check(
            "Proxy Failure After Misconfiguration",
            DEPLOYMENT_TIMEOUT_SECONDS,
            verify_proxy_failure,
        )
        print("[PASS] Proxy Failure After Misconfiguration")

        print(f"[RUN] Reverting misconfiguration commit {bad_commit_sha}")
        revert_and_push(bad_commit_sha)
        bad_commit_sha = ""

        wait_for_demo_check(
            "Proxy Recovery After Revert",
            DEPLOYMENT_TIMEOUT_SECONDS,
            verify_service_recovery,
        )
        print("[PASS] Proxy Recovery After Revert")
        print("[PASS] Misconfiguration recovery demo completed")
    finally:
        restore_original_branch(original_branch)
        if bad_commit_sha:
            print(
                "[WARN] The misconfiguration commit was created but not reverted automatically. "
                "Run `git revert --no-edit {}` and push the branch.".format(bad_commit_sha),
            )


if __name__ == "__main__":
    main()
