#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARTIFACT_ROOT="${SCRIPT_DIR}/recovery-artifacts"

ENVIRONMENT=""
ACTION="rebuild"
AUTO_APPROVE=1
VERIFY_LOCAL=1
SKIP_TERRAFORM_LOCAL=0
BECOME_PROMPT_MODE="auto"
declare -a TF_PASSTHROUGH_ARGS=()

log() {
  printf '[disaster-recovery] %s\n' "$*"
}

die() {
  printf '[disaster-recovery] %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: ./terraform/disaster-recovery.sh <local|aws|azure> [rebuild|plan] [options] [-- <terraform args>]

Commands:
  rebuild   Destroy and rebuild the selected environment. Default.
  plan      Show the destroy/apply steps that a rebuild would execute.

Options:
  --auto-approve          Auto-approve Terraform destroy/apply. Default.
  --no-auto-approve       Require interactive confirmation for destroy/apply.
  --skip-verify           Skip local post-deploy verification after a local rebuild.
  --skip-terraform        Skip the Terraform handoff refresh for the local rebuild.
  --ask-become-pass       Pass -K to the local runtime wrapper.
  --no-ask-become-pass    Do not pass -K to the local runtime wrapper.
  -h, --help              Show this help text.

Examples:
  ./terraform/disaster-recovery.sh local rebuild
  ./terraform/disaster-recovery.sh aws rebuild -- -var-file=terraform.tfvars
  ./terraform/disaster-recovery.sh azure plan -- -var-file=terraform.tfvars
EOF
}

require_command() {
  local command_name
  for command_name in "$@"; do
    command -v "${command_name}" >/dev/null 2>&1 || die "Missing required command: ${command_name}"
  done
}

run_and_log() {
  local log_file="$1"
  shift
  (
    "$@"
  ) 2>&1 | tee "${log_file}"
}

artifact_dir_for() {
  local environment="$1"
  local timestamp=""

  timestamp="$(date -u +"%Y%m%dT%H%M%SZ")"
  mkdir -p "${ARTIFACT_ROOT}/${environment}/${timestamp}"
  printf '%s\n' "${ARTIFACT_ROOT}/${environment}/${timestamp}"
}

local_runtime_command() {
  local action="$1"
  local -a command

  command=(bash "${REPO_ROOT}/local-runtime.sh" "${action}")

  if [[ "${action}" == "up" && "${VERIFY_LOCAL}" -eq 1 ]]; then
    command+=(--verify)
  fi

  if [[ "${SKIP_TERRAFORM_LOCAL}" -eq 1 && "${action}" == "up" ]]; then
    command+=(--skip-terraform)
  fi

  case "${BECOME_PROMPT_MODE}" in
    always)
      command+=(--ask-become-pass)
      ;;
    never)
      command+=(--no-ask-become-pass)
      ;;
  esac

  printf '%s\0' "${command[@]}"
}

run_local_rebuild() {
  local artifact_dir="$1"
  local -a down_command
  local -a up_command

  mapfile -d '' -t down_command < <(local_runtime_command "down")
  mapfile -d '' -t up_command < <(local_runtime_command "up")

  log "Rebuilding the local runtime"
  run_and_log "${artifact_dir}/local-runtime-down.log" "${down_command[@]}" || true
  run_and_log "${artifact_dir}/local-runtime-up.log" "${up_command[@]}"
  run_and_log "${artifact_dir}/local-runtime-status.log" bash "${REPO_ROOT}/local-runtime.sh" status --no-ask-become-pass
}

print_local_plan() {
  local verify_suffix=""

  if [[ "${VERIFY_LOCAL}" -eq 1 ]]; then
    verify_suffix=" --verify"
  fi

  cat <<EOF
Local disaster recovery rebuild plan:
  1. bash ${REPO_ROOT}/local-runtime.sh down
  2. bash ${REPO_ROOT}/local-runtime.sh up${verify_suffix}
EOF
}

terraform_env_dir() {
  case "${ENVIRONMENT}" in
    aws|azure)
      printf '%s/environments/%s\n' "${SCRIPT_DIR}" "${ENVIRONMENT}"
      ;;
    *)
      die "Unsupported Terraform environment for disaster recovery: ${ENVIRONMENT}"
      ;;
  esac
}

terraform_auto_approve_args() {
  if [[ "${AUTO_APPROVE}" -eq 1 ]]; then
    printf '%s\0' "-auto-approve"
  fi
}

run_terraform_rebuild() {
  local artifact_dir="$1"
  local env_dir=""
  local -a auto_approve_args

  env_dir="$(terraform_env_dir)"
  mapfile -d '' -t auto_approve_args < <(terraform_auto_approve_args)

  require_command terraform

  log "Initializing Terraform for ${ENVIRONMENT}"
  run_and_log "${artifact_dir}/init.log" terraform -chdir="${env_dir}" init -input=false

  log "Destroying the ${ENVIRONMENT} environment"
  run_and_log "${artifact_dir}/destroy.log" \
    terraform -chdir="${env_dir}" destroy -input=false "${auto_approve_args[@]}" "${TF_PASSTHROUGH_ARGS[@]}"

  log "Applying the ${ENVIRONMENT} environment"
  run_and_log "${artifact_dir}/apply.log" \
    terraform -chdir="${env_dir}" apply -input=false "${auto_approve_args[@]}" "${TF_PASSTHROUGH_ARGS[@]}"

  run_and_log "${artifact_dir}/outputs.log" terraform -chdir="${env_dir}" output
}

run_terraform_plan() {
  local artifact_dir="$1"
  local env_dir=""

  env_dir="$(terraform_env_dir)"
  require_command terraform

  log "Initializing Terraform for ${ENVIRONMENT}"
  run_and_log "${artifact_dir}/init.log" terraform -chdir="${env_dir}" init -input=false

  log "Planning destroy for ${ENVIRONMENT}"
  run_and_log "${artifact_dir}/plan-destroy.log" \
    terraform -chdir="${env_dir}" plan -destroy -input=false "${TF_PASSTHROUGH_ARGS[@]}"

  log "Planning apply for ${ENVIRONMENT}"
  run_and_log "${artifact_dir}/plan-apply.log" \
    terraform -chdir="${env_dir}" plan -input=false "${TF_PASSTHROUGH_ARGS[@]}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    local|aws|azure)
      ENVIRONMENT="$1"
      ;;
    rebuild|plan)
      ACTION="$1"
      ;;
    --auto-approve)
      AUTO_APPROVE=1
      ;;
    --no-auto-approve)
      AUTO_APPROVE=0
      ;;
    --skip-verify)
      VERIFY_LOCAL=0
      ;;
    --skip-terraform)
      SKIP_TERRAFORM_LOCAL=1
      ;;
    --ask-become-pass)
      BECOME_PROMPT_MODE="always"
      ;;
    --no-ask-become-pass)
      BECOME_PROMPT_MODE="never"
      ;;
    --)
      shift
      TF_PASSTHROUGH_ARGS=("$@")
      break
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
  shift
done

[[ -n "${ENVIRONMENT}" ]] || die "You must select an environment: local, aws, or azure"

artifact_dir="$(artifact_dir_for "${ENVIRONMENT}")"
log "Writing disaster recovery logs to ${artifact_dir}"

case "${ENVIRONMENT}" in
  local)
    if [[ "${ACTION}" == "plan" ]]; then
      print_local_plan | tee "${artifact_dir}/plan.log"
    else
      run_local_rebuild "${artifact_dir}"
    fi
    ;;
  aws|azure)
    if [[ "${ACTION}" == "plan" ]]; then
      run_terraform_plan "${artifact_dir}"
    else
      run_terraform_rebuild "${artifact_dir}"
    fi
    ;;
esac
