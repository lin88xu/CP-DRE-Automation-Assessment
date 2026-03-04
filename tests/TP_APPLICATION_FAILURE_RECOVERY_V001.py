#!/usr/bin/env python3

import json
import os
import subprocess
from pathlib import Path
from typing import Any, Dict, List, Tuple

from TP_REMOTE_STACK_VERIFICATION_V001 import (
    AWS_TERRAFORM_OUTPUTS,
    KONG_ADMIN_URL,
    wait_for_check,
    verify_kong_admin,
    verify_kong_proxy,
)

REPO_ROOT = Path(__file__).resolve().parent.parent
AWS_TERRAFORM_TFVARS = REPO_ROOT / "terraform/environments/aws/terraform.tfvars"
DEFAULT_NAME_PREFIX = os.getenv("AWS_NAME_PREFIX", "kong-aws")
DEFAULT_AWS_REGION = os.getenv("AWS_REGION") or os.getenv("AWS_DEFAULT_REGION") or "ap-southeast-1"
NAME_PREFIX = DEFAULT_NAME_PREFIX
AWS_REGION = DEFAULT_AWS_REGION


def _load_tfvars_defaults() -> None:
    global AWS_REGION  # noqa: PLW0603
    global NAME_PREFIX  # noqa: PLW0603

    if not AWS_TERRAFORM_TFVARS.exists():
        return

    for raw_line in AWS_TERRAFORM_TFVARS.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip().strip('"')
        if key == "aws_region" and not os.getenv("AWS_REGION") and not os.getenv("AWS_DEFAULT_REGION"):
            AWS_REGION = value
        if key == "name_prefix" and not os.getenv("AWS_NAME_PREFIX"):
            NAME_PREFIX = value


_load_tfvars_defaults()

ECS_CLUSTER_NAME = os.getenv(
    "ECS_CLUSTER_NAME",
    AWS_TERRAFORM_OUTPUTS.get("ecs_cluster_name", ""),
).strip()
ECS_SERVICE_NAME = os.getenv(
    "ECS_SERVICE_NAME",
    AWS_TERRAFORM_OUTPUTS.get("ecs_service_name", ""),
).strip()


def parse_ecs_name(arn_or_name: str) -> str:
    return arn_or_name.rsplit("/", 1)[-1]


def pick_obvious_match(candidates: List[str], description: str) -> str:
    if not candidates:
        if description == "ECS cluster":
            raise RuntimeError(
                f"no {description} candidates were found in region {AWS_REGION}. "
                "Verify that your AWS CLI is pointed at the expected account and region. "
                "Useful checks: "
                "`aws sts get-caller-identity` and "
                f"`aws --region {AWS_REGION} ecs list-clusters`.",
            )
        raise RuntimeError(f"no {description} candidates were found in region {AWS_REGION}")

    if len(candidates) == 1:
        return parse_ecs_name(candidates[0])

    prefix_matches = [candidate for candidate in candidates if NAME_PREFIX in parse_ecs_name(candidate)]
    if len(prefix_matches) == 1:
        return parse_ecs_name(prefix_matches[0])

    raise RuntimeError(
        f"could not determine a unique {description}. "
        f"Candidates: {', '.join(parse_ecs_name(candidate) for candidate in candidates)}. "
        f"Set the explicit environment variable instead.",
    )


def discover_ecs_identifiers() -> Tuple[str, str]:
    cluster_payload = aws_json(["ecs", "list-clusters"])
    cluster_arns = cluster_payload.get("clusterArns", [])
    cluster_name = pick_obvious_match(cluster_arns, "ECS cluster")

    service_payload = aws_json(["ecs", "list-services", "--cluster", cluster_name])
    service_arns = service_payload.get("serviceArns", [])
    service_name = pick_obvious_match(service_arns, "ECS service")

    return cluster_name, service_name


def ensure_ecs_identifiers_configured() -> Tuple[str, str]:
    if ECS_CLUSTER_NAME and ECS_SERVICE_NAME:
        return ECS_CLUSTER_NAME, ECS_SERVICE_NAME

    if ECS_CLUSTER_NAME and not ECS_SERVICE_NAME:
        service_payload = aws_json(["ecs", "list-services", "--cluster", ECS_CLUSTER_NAME])
        service_name = pick_obvious_match(service_payload.get("serviceArns", []), "ECS service")
        return ECS_CLUSTER_NAME, service_name

    if ECS_SERVICE_NAME and not ECS_CLUSTER_NAME:
        cluster_payload = aws_json(["ecs", "list-clusters"])
        cluster_name = pick_obvious_match(cluster_payload.get("clusterArns", []), "ECS cluster")
        return cluster_name, ECS_SERVICE_NAME

    try:
        return discover_ecs_identifiers()
    except RuntimeError as exc:
        raise RuntimeError(
            "ECS cluster/service names are not configured and automatic discovery was not unique. "
            "Set ECS_CLUSTER_NAME and ECS_SERVICE_NAME explicitly, or re-expose those Terraform outputs. "
            f"Discovery detail: {exc}",
        ) from exc


def resolved_ecs_identifiers() -> Tuple[str, str]:
    cluster_name, service_name = ensure_ecs_identifiers_configured()
    os.environ.setdefault("ECS_CLUSTER_NAME", cluster_name)
    os.environ.setdefault("ECS_SERVICE_NAME", service_name)
    return cluster_name, service_name


def run_command(args: List[str]) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        args,
        cwd=REPO_ROOT,
        capture_output=True,
        check=False,
        text=True,
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        raise RuntimeError(f"command failed ({' '.join(args)}): {detail}")
    return result


def aws_json(args: List[str]) -> Dict[str, Any]:
    result = run_command(["aws", "--region", AWS_REGION, *args, "--output", "json"])
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"AWS CLI did not return valid JSON for {' '.join(args)}") from exc


def list_service_tasks() -> List[str]:
    payload = aws_json(
        [
            "ecs",
            "list-tasks",
            "--cluster",
            ECS_CLUSTER_NAME,
            "--service-name",
            ECS_SERVICE_NAME,
        ],
    )
    return payload.get("taskArns", [])


def describe_service() -> Dict[str, Any]:
    payload = aws_json(
        [
            "ecs",
            "describe-services",
            "--cluster",
            ECS_CLUSTER_NAME,
            "--services",
            ECS_SERVICE_NAME,
        ],
    )
    services = payload.get("services", [])
    if not services:
        raise RuntimeError(f"ECS service {ECS_SERVICE_NAME} was not found in cluster {ECS_CLUSTER_NAME}")
    return services[0]


def stop_task(task_arn: str) -> None:
    run_command(
        [
            "aws",
            "--region",
            AWS_REGION,
            "ecs",
            "stop-task",
            "--cluster",
            ECS_CLUSTER_NAME,
            "--task",
            task_arn,
            "--reason",
            "assessment-demo-app-failure",
        ],
    )


def verify_service_recovery(stopped_task_arn: str) -> None:
    service = describe_service()
    if service.get("runningCount") != service.get("desiredCount"):
        raise RuntimeError(
            f"runningCount={service.get('runningCount')} desiredCount={service.get('desiredCount')}",
        )
    if service.get("pendingCount") != 0:
        raise RuntimeError(f"pendingCount={service.get('pendingCount')}")

    task_arns = list_service_tasks()
    if not task_arns:
        raise RuntimeError("service has no running tasks yet")
    if stopped_task_arn in task_arns:
        raise RuntimeError("original task is still present")

    deployments = service.get("deployments", [])
    for deployment in deployments:
        if deployment.get("status") == "PRIMARY" and deployment.get("runningCount", 0) < 1:
            raise RuntimeError("primary deployment has not recovered a running task yet")

    verify_kong_proxy()
    if KONG_ADMIN_URL:
        verify_kong_admin()


def main() -> None:
    global ECS_CLUSTER_NAME  # noqa: PLW0603
    global ECS_SERVICE_NAME  # noqa: PLW0603

    ECS_CLUSTER_NAME, ECS_SERVICE_NAME = resolved_ecs_identifiers()
    print(f"[RUN] AWS ECS application failure demo against {ECS_CLUSTER_NAME}/{ECS_SERVICE_NAME} in {AWS_REGION}")

    initial_tasks = list_service_tasks()
    if not initial_tasks:
        raise RuntimeError("no running ECS tasks were found for the service")

    stopped_task_arn = initial_tasks[0]
    print(f"[RUN] Stopping task {stopped_task_arn}")
    stop_task(stopped_task_arn)

    wait_for_check(
        "ECS Service Recovery",
        lambda: verify_service_recovery(stopped_task_arn),
    )
    print("[PASS] ECS Service Recovery")
    print("[PASS] Application failure recovery demo completed")


if __name__ == "__main__":
    main()
