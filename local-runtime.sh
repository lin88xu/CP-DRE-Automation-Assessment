#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="${ROOT_DIR}/anisible"
TERRAFORM_DIR="${ROOT_DIR}/terraform/environments/local"
GENERATED_DIR="${TERRAFORM_DIR}/generated"
GENERATED_INVENTORY="${GENERATED_DIR}/hosts.yml"
GENERATED_VARS="${GENERATED_DIR}/terraform-ansible-vars.yml"
LOCAL_INVENTORY="${ANSIBLE_DIR}/inventories/local/hosts.yml"
ANSIBLE_CONFIG_FILE="${ANSIBLE_DIR}/ansible.cfg"
ROLES_DIR="${ANSIBLE_DIR}/roles"
PLAYBOOK_DEFAULTS="${ANSIBLE_DIR}/playbooks/group_vars/all.yml"
GLOBAL_DEFAULTS="${ANSIBLE_DIR}/group_vars/all.yml"
LOCAL_RUNTIME_STATE_DIR="${ROOT_DIR}/.local-runtime"
LOCAL_FORWARD_DIR="${LOCAL_RUNTIME_STATE_DIR}/port-forward"
DEPLOYMENT_RUNTIME="local"

ACTION="toggle"
SKIP_TERRAFORM=0
BECOME_PROMPT_MODE="auto"

log() {
  printf '[local-runtime] %s\n' "$*"
}

die() {
  printf '[local-runtime] %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: ./local-runtime.sh [up|down|toggle|status] [options]

Commands:
  up                  Deploy the local stack.
  down                Tear down the local stack.
  toggle              Turn the local stack off if active, otherwise deploy it.
  status              Show whether the local stack is active.

Options:
  --skip-terraform          Skip terraform init/apply before "up".
  --ask-become-pass         Always pass -K to ansible-playbook.
  --no-ask-become-pass      Never pass -K to ansible-playbook.
  -h, --help                Show this help text.

Examples:
  ./local-runtime.sh
  ./local-runtime.sh up
  ./local-runtime.sh down
  ./local-runtime.sh status

Notes:
  The local runtime uses Minikube under the hood.
  "up" starts localhost port-forwards for Grafana, Prometheus, and Kong.
  "down" stops those port-forwards.
EOF
}

require_command() {
  local command_name
  for command_name in "$@"; do
    command -v "${command_name}" >/dev/null 2>&1 || die "Missing required command: ${command_name}"
  done
}

ensure_dir() {
  mkdir -p "$1"
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

process_is_running() {
  local pid="$1"
  [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1
}

read_pid_file() {
  local pid_file="$1"
  [[ -f "${pid_file}" ]] || return 1
  tr -d '[:space:]' < "${pid_file}"
}

port_is_listening() {
  local port="$1"
  ss -ltn "( sport = :${port} )" | tail -n +2 | grep -q .
}

wait_for_port() {
  local port="$1"
  local attempts=20

  while ((attempts > 0)); do
    if port_is_listening "${port}"; then
      return 0
    fi
    sleep 1
    attempts=$((attempts - 1))
  done

  return 1
}

stop_pid_file() {
  local pid_file="$1"
  local pid=""

  pid="$(read_pid_file "${pid_file}" 2>/dev/null || true)"
  if [[ -n "${pid}" ]] && process_is_running "${pid}"; then
    kill "${pid}" >/dev/null 2>&1 || true
    wait "${pid}" 2>/dev/null || true
  fi
  rm -f "${pid_file}"
}

read_generated_string_var() {
  local key="$1"
  [[ -f "${GENERATED_VARS}" ]] || return 1

  awk -v wanted="${key}" '
    $0 ~ "^\"" wanted "\"[[:space:]]*:" {
      line = $0
      sub("^\"" wanted "\"[[:space:]]*:[[:space:]]*", "", line)
      sub(",$", "", line)
      gsub(/^"/, "", line)
      gsub(/"$/, "", line)
      print line
      exit
    }
  ' "${GENERATED_VARS}"
}

read_group_string_var() {
  local key="$1"
  local file="$2"
  [[ -f "${file}" ]] || return 1

  awk -F':' -v wanted="${key}" '
    $1 == wanted {
      value = substr($0, index($0, ":") + 1)
      sub(/[[:space:]]+#.*$/, "", value)
      gsub(/^[[:space:]]+/, "", value)
      gsub(/[[:space:]]+$/, "", value)
      gsub(/^"/, "", value)
      gsub(/"$/, "", value)
      print value
      exit
    }
  ' "${file}"
}

resolve_var() {
  local key="$1"
  local fallback="$2"
  local value=""

  value="$(read_generated_string_var "${key}" 2>/dev/null || true)"
  if [[ -z "${value}" ]]; then
    value="$(read_group_string_var "${key}" "${PLAYBOOK_DEFAULTS}" 2>/dev/null || true)"
  fi
  if [[ -z "${value}" ]]; then
    value="$(read_group_string_var "${key}" "${GLOBAL_DEFAULTS}" 2>/dev/null || true)"
  fi
  if [[ -z "${value}" ]]; then
    value="${fallback}"
  fi

  trim "${value}"
}

MINIKUBE_PROFILE="$(resolve_var "minikube_profile" "kong-assessment")"
MINIKUBE_NAMESPACE="$(resolve_var "minikube_namespace" "kong")"

should_ask_become_pass() {
  case "${BECOME_PROMPT_MODE}" in
    always)
      return 0
      ;;
    never)
      return 1
      ;;
    auto)
      if [[ "${EUID}" -eq 0 ]]; then
        return 1
      fi
      if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
        return 1
      fi
      return 0
      ;;
    *)
      die "Unsupported become prompt mode: ${BECOME_PROMPT_MODE}"
      ;;
  esac
}

inventory_file() {
  if [[ -f "${GENERATED_INVENTORY}" ]]; then
    printf '%s\n' "${GENERATED_INVENTORY}"
  else
    printf '%s\n' "${LOCAL_INVENTORY}"
  fi
}

run_playbook() {
  local playbook="$1"
  local inventory
  local -a command

  require_command ansible-playbook
  inventory="$(inventory_file)"
  command=(ansible-playbook)

  if should_ask_become_pass; then
    command+=(-K)
  fi

  command+=(-i "${inventory}" "${playbook}")

  if [[ -f "${GENERATED_VARS}" ]]; then
    command+=(-e "@${GENERATED_VARS}")
  fi

  command+=(-e "deployment_runtime=${DEPLOYMENT_RUNTIME}")

  (
    cd "${ANSIBLE_DIR}"
    ANSIBLE_CONFIG="${ANSIBLE_CONFIG_FILE}" ANSIBLE_ROLES_PATH="${ROLES_DIR}" "${command[@]}"
  )
}

refresh_terraform_handoff() {
  require_command terraform
  log "Refreshing Terraform local handoff files"
  terraform -chdir="${TERRAFORM_DIR}" init -input=false
  terraform -chdir="${TERRAFORM_DIR}" apply -auto-approve -input=false
}

is_local_runtime_active() {
  if command -v minikube >/dev/null 2>&1 && minikube status -p "${MINIKUBE_PROFILE}" >/dev/null 2>&1; then
    return 0
  fi

  if command -v docker >/dev/null 2>&1; then
    local running_profiles
    running_profiles="$(docker ps --filter "label=name.minikube.sigs.k8s.io=${MINIKUBE_PROFILE}" --format '{{.Names}}' 2>/dev/null || true)"
    [[ -n "${running_profiles}" ]] && return 0
  fi

  return 1
}

cleanup_local_orphans() {
  local -a container_ids

  command -v docker >/dev/null 2>&1 || return 0
  mapfile -t container_ids < <(docker ps -aq --filter "label=name.minikube.sigs.k8s.io=${MINIKUBE_PROFILE}" 2>/dev/null || true)

  if ((${#container_ids[@]} > 0)); then
    log "Removing orphaned local runtime container(s) for profile ${MINIKUBE_PROFILE}"
    docker rm -f "${container_ids[@]}" >/dev/null
  fi
}

stop_local_port_forwards() {
  stop_pid_file "${LOCAL_FORWARD_DIR}/grafana.pid"
  stop_pid_file "${LOCAL_FORWARD_DIR}/prometheus.pid"
  stop_pid_file "${LOCAL_FORWARD_DIR}/kong.pid"
}

start_port_forward() {
  local name="$1"
  local ports="$2"
  local primary_port="$3"
  local pid_file="${LOCAL_FORWARD_DIR}/${name}.pid"
  local log_file="${LOCAL_FORWARD_DIR}/${name}.log"
  local pid=""

  pid="$(read_pid_file "${pid_file}" 2>/dev/null || true)"
  if [[ -n "${pid}" ]] && process_is_running "${pid}"; then
    if port_is_listening "${primary_port}"; then
      return 0
    fi
    kill "${pid}" >/dev/null 2>&1 || true
    wait "${pid}" 2>/dev/null || true
    rm -f "${pid_file}"
  fi

  if port_is_listening "${primary_port}"; then
    die "Port ${primary_port} is already in use; cannot start local ${name} port-forward"
  fi

  nohup kubectl -n "${MINIKUBE_NAMESPACE}" port-forward "svc/${name}" ${ports} >"${log_file}" 2>&1 &
  pid=$!
  printf '%s\n' "${pid}" > "${pid_file}"

  if ! wait_for_port "${primary_port}"; then
    tail -n 20 "${log_file}" >&2 || true
    die "Failed to start local ${name} port-forward on localhost:${primary_port}"
  fi
}

start_local_port_forwards() {
  require_command kubectl ss
  ensure_dir "${LOCAL_FORWARD_DIR}"

  log "Starting localhost port-forwards for the local services"
  start_port_forward "grafana" "3000:3000" "3000"
  start_port_forward "prometheus" "9090:9090" "9090"
  start_port_forward "kong" "8000:8000 8001:8001 8002:8002" "8000"
}

print_local_urls() {
  cat <<EOF
Local URLs:
  Grafana: http://127.0.0.1:3000
  Prometheus: http://127.0.0.1:9090
  Kong Proxy: http://127.0.0.1:8000
  Kong Admin API: http://127.0.0.1:8001
  Kong Manager UI: http://127.0.0.1:8002
  Grafana login: admin/admin
EOF
}

teardown_local_runtime() {
  log "Tearing down the local runtime"
  stop_local_port_forwards
  run_playbook "playbooks/teardown.yml"
  cleanup_local_orphans
}

deploy_local_runtime() {
  if [[ "${SKIP_TERRAFORM}" -eq 0 ]]; then
    refresh_terraform_handoff
  elif [[ ! -f "${GENERATED_INVENTORY}" ]]; then
    log "Terraform handoff files are missing; using the local fallback inventory"
  fi

  log "Deploying the local runtime"
  run_playbook "playbooks/site.yml"
  start_local_port_forwards
  print_local_urls
}

print_status() {
  if is_local_runtime_active; then
    printf 'Local runtime status: local\n'
  else
    printf 'Local runtime status: off\n'
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    up|down|toggle|status)
      ACTION="$1"
      ;;
    local|minikube)
      ;;
    --skip-terraform)
      SKIP_TERRAFORM=1
      ;;
    --ask-become-pass)
      BECOME_PROMPT_MODE="always"
      ;;
    --no-ask-become-pass)
      BECOME_PROMPT_MODE="never"
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

case "${ACTION}" in
  status)
    print_status
    ;;
  down)
    teardown_local_runtime
    print_status
    ;;
  up)
    deploy_local_runtime
    print_status
    ;;
  toggle)
    if is_local_runtime_active; then
      teardown_local_runtime
    else
      deploy_local_runtime
    fi
    print_status
    ;;
esac
