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
ANSIBLE_SECRET_DIR="${ANSIBLE_SECRET_CACHE_DIR:-${ANSIBLE_DIR}/.secrets}"
LOCAL_RUNTIME_STATE_DIR="${LOCAL_RUNTIME_STATE_DIR_OVERRIDE:-${ROOT_DIR}/.local-runtime}"
LOCAL_FORWARD_DIR="${LOCAL_RUNTIME_STATE_DIR}/port-forward"
ROLLBACK_STATE_DIR="${LOCAL_RUNTIME_STATE_DIR}/rollback"
ROLLBACK_METADATA_FILE="${ROLLBACK_STATE_DIR}/last-known-good.env"
DEPLOYMENT_RUNTIME="local"

ACTION="toggle"
SKIP_TERRAFORM=0
BECOME_PROMPT_MODE="auto"
VERIFY_AFTER_DEPLOY=0
AUTO_ROLLBACK=0
ROLLBACK_REF=""
ROLLBACK_NESTED=0
ALLOW_DIRTY_SNAPSHOT=0

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
  rollback            Redeploy the last verified-good local stack revision.
  toggle              Turn the local stack off if active, otherwise deploy it.
  status              Show whether the local stack is active.

Options:
  --skip-terraform          Skip terraform init/apply before "up".
  --verify                  Run local verification tests after "up".
  --auto-rollback           If deploy or verification fails, redeploy the last verified-good revision.
  --allow-dirty-snapshot    Record a rollback snapshot even if the git worktree has local edits.
  --rollback-ref <git-ref>  Override the git ref used by "rollback".
  --ask-become-pass         Always pass -K to ansible-playbook.
  --no-ask-become-pass      Never pass -K to ansible-playbook.
  -h, --help                Show this help text.

Examples:
  ./local-runtime.sh
  ./local-runtime.sh up
  ./local-runtime.sh up --verify --auto-rollback
  ./local-runtime.sh up --verify --allow-dirty-snapshot
  ./local-runtime.sh down
  ./local-runtime.sh rollback
  ./local-runtime.sh status

Notes:
  The local runtime uses Minikube under the hood.
  "up" starts localhost port-forwards for Grafana, Prometheus, and Kong.
  "down" stops those port-forwards.
  Verified-good revisions are recorded only from clean git commits.
EOF
}

require_command() {
  local command_name
  for command_name in "$@"; do
    command -v "${command_name}" >/dev/null 2>&1 || die "Missing required command: ${command_name}"
  done
}

warn() {
  printf '[local-runtime] %s\n' "$*" >&2
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

git_available() {
  command -v git >/dev/null 2>&1 && git -C "${ROOT_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

current_git_commit() {
  git_available || return 1
  git -C "${ROOT_DIR}" rev-parse HEAD
}

current_git_commit_short() {
  git_available || return 1
  git -C "${ROOT_DIR}" rev-parse --short HEAD
}

current_git_head_subject() {
  git_available || return 1
  git -C "${ROOT_DIR}" show -s --format=%s HEAD
}

current_git_commit_timestamp() {
  git_available || return 1
  git -C "${ROOT_DIR}" show -s --format=%cI HEAD
}

current_git_dirty() {
  git_available || return 1
  if git -C "${ROOT_DIR}" diff --name-only --no-ext-diff | grep -v '^.local-runtime/' | grep -q .; then
    return 0
  fi

  if git -C "${ROOT_DIR}" diff --cached --name-only --no-ext-diff | grep -v '^.local-runtime/' | grep -q .; then
    return 0
  fi

  if git -C "${ROOT_DIR}" ls-files --others --exclude-standard | grep -v '^.local-runtime/' | grep -q .; then
    return 0
  fi

  return 1
}

write_rollback_metadata() {
  local ref="$1"
  local commit_short="$2"
  local commit_subject="$3"
  local commit_timestamp="$4"

  ensure_dir "${ROLLBACK_STATE_DIR}"
  {
    printf 'LAST_KNOWN_GOOD_REF=%q\n' "${ref}"
    printf 'LAST_KNOWN_GOOD_COMMIT_SHORT=%q\n' "${commit_short}"
    printf 'LAST_KNOWN_GOOD_SUBJECT=%q\n' "${commit_subject}"
    printf 'LAST_KNOWN_GOOD_COMMIT_TIMESTAMP=%q\n' "${commit_timestamp}"
    printf 'LAST_KNOWN_GOOD_RECORDED_AT=%q\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  } > "${ROLLBACK_METADATA_FILE}"
}

load_rollback_metadata() {
  [[ -f "${ROLLBACK_METADATA_FILE}" ]] || return 1
  # shellcheck disable=SC1090
  source "${ROLLBACK_METADATA_FILE}"
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

read_secret_file() {
  local key="$1"
  local secret_file="${ANSIBLE_SECRET_DIR}/localhost-${key}"

  if [[ ! -f "${secret_file}" ]]; then
    secret_file="${ANSIBLE_SECRET_DIR}/localhost/${key}"
  fi

  [[ -f "${secret_file}" ]] || return 1
  tr -d '\r\n' < "${secret_file}"
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

sanitized_generated_vars_file() {
  local sanitized_file="${LOCAL_RUNTIME_STATE_DIR}/terraform-ansible-vars.sanitized.yml"

  [[ -f "${GENERATED_VARS}" ]] || return 1
  ensure_dir "${LOCAL_RUNTIME_STATE_DIR}"

  awk '
    $0 == "\"observability_grafana_admin_user\": \"\"" { next }
    $0 == "\"observability_grafana_admin_password\": \"\"" { next }
    { print }
  ' "${GENERATED_VARS}" > "${sanitized_file}"

  printf '%s\n' "${sanitized_file}"
}

run_playbook() {
  local playbook="$1"
  local inventory
  local generated_vars_file=""
  local -a command

  require_command ansible-playbook
  inventory="$(inventory_file)"
  command=(ansible-playbook)

  if should_ask_become_pass; then
    command+=(-K)
  fi

  command+=(-i "${inventory}" "${playbook}")

  if generated_vars_file="$(sanitized_generated_vars_file 2>/dev/null)"; then
    command+=(-e "@${generated_vars_file}")
  elif [[ -f "${GENERATED_VARS}" ]]; then
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

record_last_known_good_revision() {
  local commit_ref=""
  local commit_short=""
  local commit_subject=""
  local commit_timestamp=""

  if ! git_available; then
    warn "Skipping rollback snapshot: git metadata is unavailable"
    return 0
  fi

  if current_git_dirty; then
    if [[ "${ALLOW_DIRTY_SNAPSHOT}" -ne 1 ]]; then
      warn "Skipping rollback snapshot: working tree is dirty, so the deployment is not reproducible by git ref"
      return 0
    fi
    warn "Recording rollback snapshot despite dirty working tree because --allow-dirty-snapshot was set"
  fi

  commit_ref="$(current_git_commit)"
  commit_short="$(current_git_commit_short)"
  commit_subject="$(current_git_head_subject)"
  commit_timestamp="$(current_git_commit_timestamp)"
  write_rollback_metadata "${commit_ref}" "${commit_short}" "${commit_subject}" "${commit_timestamp}"
  log "Recorded verified-good rollback snapshot at ${commit_short}"
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
  local grafana_user="grafana-admin"
  local grafana_password="(generated during deploy)"

  if [[ -n "${GRAFANA_ADMIN_USER:-}" ]]; then
    grafana_user="${GRAFANA_ADMIN_USER}"
  else
    grafana_user="$(trim "$(resolve_var "observability_grafana_admin_user" "${grafana_user}")")"
  fi

  if [[ -n "${GRAFANA_ADMIN_PASSWORD:-}" ]]; then
    grafana_password="${GRAFANA_ADMIN_PASSWORD}"
  fi
  if [[ -f "${ANSIBLE_SECRET_DIR}/localhost-grafana_admin_password" ]] || [[ -f "${ANSIBLE_SECRET_DIR}/localhost/grafana_admin_password" ]]; then
    grafana_password="$(read_secret_file "grafana_admin_password")"
  fi

  cat <<EOF
Local URLs:
  Grafana: http://127.0.0.1:3000
  Prometheus: http://127.0.0.1:9090
  Kong Proxy: http://127.0.0.1:8000
  Kong Admin API: http://127.0.0.1:8001
  Kong Manager UI: http://127.0.0.1:8002
  Grafana login: ${grafana_user}/${grafana_password}
EOF
}

resolve_grafana_admin_user() {
  if [[ -n "${GRAFANA_ADMIN_USER:-}" ]]; then
    printf '%s\n' "${GRAFANA_ADMIN_USER}"
    return 0
  fi

  trim "$(resolve_var "observability_grafana_admin_user" "grafana-admin")"
}

resolve_grafana_admin_password() {
  if [[ -n "${GRAFANA_ADMIN_PASSWORD:-}" ]]; then
    printf '%s\n' "${GRAFANA_ADMIN_PASSWORD}"
    return 0
  fi

  read_secret_file "grafana_admin_password" 2>/dev/null || printf '%s' ''
}

reconcile_grafana_admin_credentials() {
  local grafana_password=""
  local grafana_pod=""
  local reset_output=""

  grafana_password="$(resolve_grafana_admin_password)"
  if [[ -z "${grafana_password}" ]]; then
    warn "Skipping Grafana credential reconciliation: no admin password is available"
    return 0
  fi

  require_command kubectl
  if ! kubectl -n "${MINIKUBE_NAMESPACE}" rollout status deployment/grafana --timeout=240s >/dev/null 2>&1; then
    warn "Skipping Grafana credential reconciliation: deployment/grafana is not ready"
    return 0
  fi

  grafana_pod="$(kubectl -n "${MINIKUBE_NAMESPACE}" get pods -l app=grafana -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  if [[ -z "${grafana_pod}" ]]; then
    warn "Skipping Grafana credential reconciliation: no Grafana pod was found"
    return 0
  fi

  if reset_output="$(kubectl -n "${MINIKUBE_NAMESPACE}" exec "${grafana_pod}" -- \
    grafana cli --homepath /usr/share/grafana admin reset-admin-password "${grafana_password}" 2>&1)"; then
    log "Reconciled Grafana admin password in pod ${grafana_pod}"
    return 0
  fi

  if reset_output="$(kubectl -n "${MINIKUBE_NAMESPACE}" exec "${grafana_pod}" -- \
    grafana-cli admin reset-admin-password "${grafana_password}" 2>&1)"; then
    log "Reconciled Grafana admin password in pod ${grafana_pod}"
    return 0
  fi

  warn "Grafana admin password reset failed in pod ${grafana_pod}; continuing with verification"
  warn "Grafana reset output: ${reset_output}"
  return 0
}

verify_local_runtime() {
  require_command python3
  log "Verifying the local runtime"
  reconcile_grafana_admin_credentials
  python3 "${ROOT_DIR}/tests/TP_LOCAL_STACK_VERIFICATION_V001.py"
  GRAFANA_USER="$(resolve_grafana_admin_user)" \
  GRAFANA_PASSWORD="$(resolve_grafana_admin_password)" \
  python3 "${ROOT_DIR}/tests/TP_DASHBOARD_CONTENT_CORRECTNESS_V001.py"
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

deploy_and_optionally_verify() {
  deploy_local_runtime
  if [[ "${VERIFY_AFTER_DEPLOY}" -eq 1 ]]; then
    verify_local_runtime
    record_last_known_good_revision
  fi
}

run_nested_up() {
  local worktree_dir="$1"
  local -a command

  command=(bash "${worktree_dir}/local-runtime.sh" up --verify)

  if [[ "${SKIP_TERRAFORM}" -eq 1 ]]; then
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

  LOCAL_RUNTIME_STATE_DIR_OVERRIDE="${LOCAL_RUNTIME_STATE_DIR}" \
  LOCAL_RUNTIME_NESTED_ROLLBACK=1 \
  "${command[@]}"
}

perform_rollback() {
  local target_ref="$1"
  local worktree_dir=""
  local teardown_status=0
  local rollback_status=0

  require_command git mktemp
  git -C "${ROOT_DIR}" rev-parse --verify --quiet "${target_ref}^{commit}" >/dev/null \
    || die "Rollback ref does not resolve to a commit: ${target_ref}"

  worktree_dir="$(mktemp -d "${TMPDIR:-/tmp}/local-runtime-rollback.XXXXXX")"
  git -C "${ROOT_DIR}" worktree add --detach "${worktree_dir}" "${target_ref}" >/dev/null

  log "Rolling back the local runtime to ${target_ref}"
  if ! teardown_local_runtime; then
    teardown_status=$?
    warn "Teardown before rollback reported a failure (status ${teardown_status}); continuing with rollback deploy"
  fi

  if ! run_nested_up "${worktree_dir}"; then
    rollback_status=$?
  fi

  git -C "${ROOT_DIR}" worktree remove --force "${worktree_dir}" >/dev/null 2>&1 || true
  rm -rf "${worktree_dir}" >/dev/null 2>&1 || true

  if [[ "${rollback_status}" -ne 0 ]]; then
    die "Rollback deployment failed for ref ${target_ref}"
  fi
}

rollback_target_ref() {
  if [[ -n "${ROLLBACK_REF}" ]]; then
    printf '%s\n' "${ROLLBACK_REF}"
    return 0
  fi

  load_rollback_metadata || die "No verified-good rollback snapshot has been recorded yet"
  printf '%s\n' "${LAST_KNOWN_GOOD_REF}"
}

attempt_auto_rollback() {
  local rollback_ref=""

  if [[ "${AUTO_ROLLBACK}" -ne 1 ]]; then
    return 1
  fi

  if ! rollback_ref="$(rollback_target_ref 2>/dev/null)"; then
    warn "Deploy failed and no verified-good rollback snapshot is available"
    return 1
  fi

  if git_available; then
    local current_ref=""
    current_ref="$(current_git_commit 2>/dev/null || true)"
    if [[ -n "${current_ref}" && "${current_ref}" == "${rollback_ref}" ]]; then
      warn "Auto rollback skipped because the current commit already matches the last verified-good snapshot"
      return 1
    fi
  fi

  warn "Deploy failed; attempting automated rollback to ${rollback_ref}"
  perform_rollback "${rollback_ref}"
  return 0
}

print_status() {
  if is_local_runtime_active; then
    printf 'Local runtime status: local\n'
  else
    printf 'Local runtime status: off\n'
  fi

  if load_rollback_metadata 2>/dev/null; then
    printf 'Last verified-good rollback snapshot: %s (%s)\n' "${LAST_KNOWN_GOOD_COMMIT_SHORT}" "${LAST_KNOWN_GOOD_SUBJECT}"
  else
    printf 'Last verified-good rollback snapshot: none\n'
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    up|down|toggle|status|rollback)
      ACTION="$1"
      ;;
    local|minikube)
      ;;
    --skip-terraform)
      SKIP_TERRAFORM=1
      ;;
    --verify)
      VERIFY_AFTER_DEPLOY=1
      ;;
    --auto-rollback)
      AUTO_ROLLBACK=1
      VERIFY_AFTER_DEPLOY=1
      ;;
    --allow-dirty-snapshot)
      ALLOW_DIRTY_SNAPSHOT=1
      ;;
    --rollback-ref)
      shift
      [[ $# -gt 0 ]] || die "Missing value for --rollback-ref"
      ROLLBACK_REF="$1"
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
      if [[ "${ACTION}" == "rollback" && -z "${ROLLBACK_REF}" ]]; then
        ROLLBACK_REF="$1"
      else
        die "Unknown argument: $1"
      fi
      ;;
  esac
  shift
done

if [[ -n "${LOCAL_RUNTIME_NESTED_ROLLBACK:-}" ]]; then
  ROLLBACK_NESTED=1
fi

case "${ACTION}" in
  status)
    print_status
    ;;
  down)
    teardown_local_runtime
    print_status
    ;;
  up)
    if [[ "${AUTO_ROLLBACK}" -eq 1 && "${ROLLBACK_NESTED}" -eq 0 ]]; then
      if ! (deploy_and_optionally_verify); then
        attempt_auto_rollback || exit 1
      fi
    else
      deploy_and_optionally_verify
    fi
    print_status
    ;;
  rollback)
    perform_rollback "$(rollback_target_ref)"
    print_status
    ;;
  toggle)
    if is_local_runtime_active; then
      teardown_local_runtime
    else
      deploy_and_optionally_verify
    fi
    print_status
    ;;
esac
