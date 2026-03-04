#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_BACKUP_ROOT="${ROOT_DIR}/.backups"
MINIKUBE_NAMESPACE="${MINIKUBE_NAMESPACE:-kong}"
MINIKUBE_POSTGRES_PVC_NAME="${MINIKUBE_POSTGRES_PVC_NAME:-kong-db-storage}"
MINIKUBE_PROMETHEUS_PVC_NAME="${MINIKUBE_PROMETHEUS_PVC_NAME:-prometheus-storage}"
MINIKUBE_GRAFANA_PVC_NAME="${MINIKUBE_GRAFANA_PVC_NAME:-grafana-storage}"

ACTION="inspect"
STACK=""
OUTPUT_DIR=""
INPUT_DIR=""
FORCE_RESTORE=0

log() {
  printf '[persistent-data] %s\n' "$*"
}

die() {
  printf '[persistent-data] %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: ./persistent-data.sh <inspect|backup|restore> <stack> [options]

Stacks:
  deployment-kong     Docker Compose Kong stack under deployment/kong
  observability       Docker Compose Prometheus/Grafana stack under promethusGrafana
  azure-host-kong     Docker Compose Kong stack deployed under /opt/kong on the Azure VM
  local-minikube      Local Minikube Kong Postgres, Prometheus, and Grafana persistent volumes
  local-compose       Convenience alias for deployment-kong + observability during backup/inspect

Options:
  --output-dir <dir>  Backup destination root. Default: ./.backups
  --input-dir <dir>   Restore source directory created by this script
  --force             Restore into existing volumes even if the stack is still running
  -h, --help          Show this help text

Examples:
  ./persistent-data.sh inspect deployment-kong
  ./persistent-data.sh backup deployment-kong
  ./persistent-data.sh backup observability --output-dir /tmp/backups
  ./persistent-data.sh backup local-minikube
  ./persistent-data.sh restore azure-host-kong --input-dir /var/backups/kong/azure-host-kong-20260304T120000Z
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

resolve_stack_metadata() {
  local stack="$1"

  case "${stack}" in
    deployment-kong)
      STACK_PROJECT="kong"
      STACK_COMPOSE_DIR="${ROOT_DIR}/deployment/kong"
      STACK_BACKUP_COMPOSE_DIR=0
      ;;
    observability)
      STACK_PROJECT="promethusGrafana"
      STACK_COMPOSE_DIR="${ROOT_DIR}/promethusGrafana"
      STACK_BACKUP_COMPOSE_DIR=0
      ;;
    azure-host-kong)
      STACK_PROJECT="kong"
      STACK_COMPOSE_DIR="/opt/kong"
      STACK_BACKUP_COMPOSE_DIR=1
      ;;
    local-minikube)
      STACK_PROJECT="local-minikube"
      STACK_COMPOSE_DIR=""
      STACK_BACKUP_COMPOSE_DIR=0
      ;;
    *)
      die "Unsupported stack: ${stack}"
      ;;
  esac
}

compose_file_path() {
  local compose_dir="$1"
  printf '%s/docker-compose.yml\n' "${compose_dir}"
}

compose_file_exists() {
  local compose_dir="$1"
  [[ -f "$(compose_file_path "${compose_dir}")" ]]
}

stack_container_count() {
  local project="$1"
  docker ps -q --filter "label=com.docker.compose.project=${project}" | wc -l
}

discover_stack_volumes() {
  local project="$1"
  docker volume ls -q --filter "label=com.docker.compose.project=${project}" | sort
}

volume_backup_file_name() {
  local volume_name="$1"
  printf '%s.tgz\n' "${volume_name}"
}

backup_single_volume() {
  local volume_name="$1"
  local backup_dir="$2"
  local backup_file=""

  backup_file="$(volume_backup_file_name "${volume_name}")"
  docker run --rm \
    -v "${volume_name}:/source:ro" \
    -v "${backup_dir}:/backup" \
    alpine:3.20 \
    sh -c "tar -C /source -czf /backup/${backup_file} ."
}

restore_single_volume() {
  local volume_name="$1"
  local backup_dir="$2"
  local backup_file=""

  backup_file="$(volume_backup_file_name "${volume_name}")"
  [[ -f "${backup_dir}/${backup_file}" ]] || die "Missing backup archive for volume ${volume_name}: ${backup_file}"

  if ! docker volume inspect "${volume_name}" >/dev/null 2>&1; then
    docker volume create "${volume_name}" >/dev/null
  fi

  docker run --rm \
    -v "${volume_name}:/restore" \
    -v "${backup_dir}:/backup:ro" \
    alpine:3.20 \
    sh -c "rm -rf /restore/* /restore/.[!.]* /restore/..?* 2>/dev/null || true; tar -C /restore -xzf /backup/${backup_file}"
}

backup_compose_dir() {
  local compose_dir="$1"
  local backup_dir="$2"

  tar -C "$(dirname "${compose_dir}")" -czf "${backup_dir}/compose-dir.tgz" "$(basename "${compose_dir}")"
}

restore_compose_dir() {
  local compose_dir="$1"
  local backup_dir="$2"

  [[ -f "${backup_dir}/compose-dir.tgz" ]] || die "Missing compose directory archive"
  mkdir -p "$(dirname "${compose_dir}")"
  tar -C "$(dirname "${compose_dir}")" -xzf "${backup_dir}/compose-dir.tgz"
}

write_metadata() {
  local stack="$1"
  local backup_dir="$2"

  {
    printf 'STACK_NAME=%q\n' "${stack}"
    printf 'STACK_PROJECT=%q\n' "${STACK_PROJECT}"
    printf 'STACK_COMPOSE_DIR=%q\n' "${STACK_COMPOSE_DIR}"
    printf 'STACK_BACKUP_COMPOSE_DIR=%q\n' "${STACK_BACKUP_COMPOSE_DIR}"
    printf 'CREATED_AT=%q\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  } > "${backup_dir}/metadata.env"
}

load_metadata() {
  local input_dir="$1"
  [[ -f "${input_dir}/metadata.env" ]] || die "Missing metadata.env in ${input_dir}"
  # shellcheck disable=SC1090
  source "${input_dir}/metadata.env"
}

write_volume_manifest() {
  local backup_dir="$1"
  shift
  printf '%s\n' "$@" > "${backup_dir}/volumes.txt"
}

read_volume_manifest() {
  local input_dir="$1"
  [[ -f "${input_dir}/volumes.txt" ]] || die "Missing volumes.txt in ${input_dir}"
  mapfile -t MANIFEST_VOLUMES < "${input_dir}/volumes.txt"
}

stop_stack_if_possible() {
  local compose_dir="$1"
  local project="$2"

  if [[ "${FORCE_RESTORE}" -eq 1 ]]; then
    return 0
  fi

  if [[ "$(stack_container_count "${project}")" -gt 0 ]]; then
    if compose_file_exists "${compose_dir}"; then
      log "Stopping stack ${project} before restore"
      docker compose --project-directory "${compose_dir}" down
    else
      die "Stack ${project} is running and ${compose_dir} has no docker-compose.yml; rerun with --force only if you have already stopped writers"
    fi
  fi
}

start_stack_if_possible() {
  local compose_dir="$1"

  if compose_file_exists "${compose_dir}"; then
    log "Starting stack from ${compose_dir}"
    docker compose --project-directory "${compose_dir}" up -d
  fi
}

inspect_single_stack() {
  local stack="$1"
  local -a volumes

  resolve_stack_metadata "${stack}"
  mapfile -t volumes < <(discover_stack_volumes "${STACK_PROJECT}")

  printf 'Stack: %s\n' "${stack}"
  printf 'Project: %s\n' "${STACK_PROJECT}"
  printf 'Compose dir: %s\n' "${STACK_COMPOSE_DIR}"
  printf 'Compose file present: %s\n' "$(compose_file_exists "${STACK_COMPOSE_DIR}" && printf yes || printf no)"
  if ((${#volumes[@]} == 0)); then
    printf 'Volumes: none discovered\n'
  else
    printf 'Volumes:\n'
    printf '  %s\n' "${volumes[@]}"
  fi
}

kube_helper_pod_name() {
  local claim_name="$1"
  printf 'persistent-data-%s\n' "${claim_name}"
}

delete_kube_helper_pod() {
  local pod_name="$1"
  kubectl -n "${MINIKUBE_NAMESPACE}" delete pod "${pod_name}" --ignore-not-found >/dev/null 2>&1 || true
}

create_kube_helper_pod() {
  local claim_name="$1"
  local pod_name=""

  pod_name="$(kube_helper_pod_name "${claim_name}")"
  delete_kube_helper_pod "${pod_name}"

  kubectl -n "${MINIKUBE_NAMESPACE}" apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${pod_name}
spec:
  restartPolicy: Never
  containers:
    - name: helper
      image: alpine:3.20
      command: ["/bin/sh", "-c", "sleep 3600"]
      volumeMounts:
        - name: storage
          mountPath: /data
  volumes:
    - name: storage
      persistentVolumeClaim:
        claimName: ${claim_name}
EOF

  kubectl -n "${MINIKUBE_NAMESPACE}" wait --for=condition=Ready "pod/${pod_name}" --timeout=180s >/dev/null
  printf '%s\n' "${pod_name}"
}

scale_kube_deployment() {
  local deployment_name="$1"
  local replicas="$2"
  kubectl -n "${MINIKUBE_NAMESPACE}" scale "deployment/${deployment_name}" --replicas="${replicas}" >/dev/null
}

wait_for_kube_deployment() {
  local deployment_name="$1"
  kubectl -n "${MINIKUBE_NAMESPACE}" rollout status "deployment/${deployment_name}" --timeout=240s >/dev/null
}

wait_for_kube_pods_gone() {
  local app_label="$1"
  kubectl -n "${MINIKUBE_NAMESPACE}" wait --for=delete pod -l "app=${app_label}" --timeout=180s >/dev/null 2>&1 || true
}

require_kube_pvc() {
  local claim_name="$1"

  kubectl -n "${MINIKUBE_NAMESPACE}" get pvc "${claim_name}" >/dev/null 2>&1 || die \
    "PVC ${claim_name} was not found in namespace ${MINIKUBE_NAMESPACE}. Redeploy the local Minikube stack so the persistent-volume manifests are applied."
}

inspect_local_minikube() {
  require_command kubectl
  printf 'Stack: local-minikube\n'
  printf 'Namespace: %s\n' "${MINIKUBE_NAMESPACE}"
  require_kube_pvc "${MINIKUBE_POSTGRES_PVC_NAME}"
  require_kube_pvc "${MINIKUBE_PROMETHEUS_PVC_NAME}"
  require_kube_pvc "${MINIKUBE_GRAFANA_PVC_NAME}"
  kubectl -n "${MINIKUBE_NAMESPACE}" get pvc "${MINIKUBE_POSTGRES_PVC_NAME}" "${MINIKUBE_PROMETHEUS_PVC_NAME}" "${MINIKUBE_GRAFANA_PVC_NAME}"
}

backup_local_minikube() {
  local backup_root="$1"
  local backup_dir=""
  local timestamp=""
  local helper_pod=""

  require_command kubectl
  require_kube_pvc "${MINIKUBE_POSTGRES_PVC_NAME}"
  require_kube_pvc "${MINIKUBE_PROMETHEUS_PVC_NAME}"
  require_kube_pvc "${MINIKUBE_GRAFANA_PVC_NAME}"

  timestamp="$(date -u +"%Y%m%dT%H%M%SZ")"
  backup_dir="${backup_root}/local-minikube-${timestamp}"
  ensure_dir "${backup_dir}"

  {
    printf 'STACK_NAME=%q\n' "local-minikube"
    printf 'MINIKUBE_NAMESPACE=%q\n' "${MINIKUBE_NAMESPACE}"
    printf 'CREATED_AT=%q\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  } > "${backup_dir}/metadata.env"

  printf '%s\n' "${MINIKUBE_POSTGRES_PVC_NAME}" "${MINIKUBE_PROMETHEUS_PVC_NAME}" "${MINIKUBE_GRAFANA_PVC_NAME}" > "${backup_dir}/volumes.txt"

  helper_pod="$(create_kube_helper_pod "${MINIKUBE_POSTGRES_PVC_NAME}")"
  log "Backing up local Minikube PVC ${MINIKUBE_POSTGRES_PVC_NAME}"
  kubectl -n "${MINIKUBE_NAMESPACE}" exec "${helper_pod}" -- tar -C /data -czf - . > "${backup_dir}/${MINIKUBE_POSTGRES_PVC_NAME}.tgz"
  delete_kube_helper_pod "${helper_pod}"

  helper_pod="$(create_kube_helper_pod "${MINIKUBE_PROMETHEUS_PVC_NAME}")"
  log "Backing up local Minikube PVC ${MINIKUBE_PROMETHEUS_PVC_NAME}"
  kubectl -n "${MINIKUBE_NAMESPACE}" exec "${helper_pod}" -- tar -C /data -czf - . > "${backup_dir}/${MINIKUBE_PROMETHEUS_PVC_NAME}.tgz"
  delete_kube_helper_pod "${helper_pod}"

  helper_pod="$(create_kube_helper_pod "${MINIKUBE_GRAFANA_PVC_NAME}")"
  log "Backing up local Minikube PVC ${MINIKUBE_GRAFANA_PVC_NAME}"
  kubectl -n "${MINIKUBE_NAMESPACE}" exec "${helper_pod}" -- tar -C /data -czf - . > "${backup_dir}/${MINIKUBE_GRAFANA_PVC_NAME}.tgz"
  delete_kube_helper_pod "${helper_pod}"

  log "Backup complete: ${backup_dir}"
}

restore_local_minikube() {
  local input_dir="$1"
  local helper_pod=""

  require_command kubectl
  require_kube_pvc "${MINIKUBE_POSTGRES_PVC_NAME}"
  require_kube_pvc "${MINIKUBE_PROMETHEUS_PVC_NAME}"
  require_kube_pvc "${MINIKUBE_GRAFANA_PVC_NAME}"

  [[ -f "${input_dir}/${MINIKUBE_POSTGRES_PVC_NAME}.tgz" ]] || die "Missing ${MINIKUBE_POSTGRES_PVC_NAME}.tgz in ${input_dir}"
  [[ -f "${input_dir}/${MINIKUBE_PROMETHEUS_PVC_NAME}.tgz" ]] || die "Missing ${MINIKUBE_PROMETHEUS_PVC_NAME}.tgz in ${input_dir}"
  [[ -f "${input_dir}/${MINIKUBE_GRAFANA_PVC_NAME}.tgz" ]] || die "Missing ${MINIKUBE_GRAFANA_PVC_NAME}.tgz in ${input_dir}"

  if [[ "${FORCE_RESTORE}" -ne 1 ]]; then
    log "Scaling down local Minikube Kong, Postgres, Prometheus, and Grafana before restore"
    scale_kube_deployment "kong" 0
    scale_kube_deployment "kong-db" 0
    scale_kube_deployment "prometheus" 0
    scale_kube_deployment "grafana" 0
    wait_for_kube_pods_gone "kong"
    wait_for_kube_pods_gone "kong-db"
    wait_for_kube_pods_gone "prometheus"
    wait_for_kube_pods_gone "grafana"
  fi

  helper_pod="$(create_kube_helper_pod "${MINIKUBE_POSTGRES_PVC_NAME}")"
  log "Restoring local Minikube PVC ${MINIKUBE_POSTGRES_PVC_NAME}"
  kubectl -n "${MINIKUBE_NAMESPACE}" exec -i "${helper_pod}" -- sh -c \
    'rm -rf /data/* /data/.[!.]* /data/..?* 2>/dev/null || true; tar -C /data -xzf -' \
    < "${input_dir}/${MINIKUBE_POSTGRES_PVC_NAME}.tgz"
  delete_kube_helper_pod "${helper_pod}"

  helper_pod="$(create_kube_helper_pod "${MINIKUBE_PROMETHEUS_PVC_NAME}")"
  log "Restoring local Minikube PVC ${MINIKUBE_PROMETHEUS_PVC_NAME}"
  kubectl -n "${MINIKUBE_NAMESPACE}" exec -i "${helper_pod}" -- sh -c \
    'rm -rf /data/* /data/.[!.]* /data/..?* 2>/dev/null || true; tar -C /data -xzf -' \
    < "${input_dir}/${MINIKUBE_PROMETHEUS_PVC_NAME}.tgz"
  delete_kube_helper_pod "${helper_pod}"

  helper_pod="$(create_kube_helper_pod "${MINIKUBE_GRAFANA_PVC_NAME}")"
  log "Restoring local Minikube PVC ${MINIKUBE_GRAFANA_PVC_NAME}"
  kubectl -n "${MINIKUBE_NAMESPACE}" exec -i "${helper_pod}" -- sh -c \
    'rm -rf /data/* /data/.[!.]* /data/..?* 2>/dev/null || true; tar -C /data -xzf -' \
    < "${input_dir}/${MINIKUBE_GRAFANA_PVC_NAME}.tgz"
  delete_kube_helper_pod "${helper_pod}"

  if [[ "${FORCE_RESTORE}" -ne 1 ]]; then
    log "Scaling local Minikube Postgres, Kong, Prometheus, and Grafana back up after restore"
    scale_kube_deployment "kong-db" 1
    wait_for_kube_deployment "kong-db"
    scale_kube_deployment "kong" 1
    scale_kube_deployment "prometheus" 1
    scale_kube_deployment "grafana" 1
    wait_for_kube_deployment "kong"
    wait_for_kube_deployment "prometheus"
    wait_for_kube_deployment "grafana"
  fi

  log "Restore complete from ${input_dir}"
}

backup_single_stack() {
  local stack="$1"
  local backup_root="$2"
  local backup_dir=""
  local timestamp=""
  local -a volumes

  resolve_stack_metadata "${stack}"
  mapfile -t volumes < <(discover_stack_volumes "${STACK_PROJECT}")
  ((${#volumes[@]} > 0)) || die "No Docker volumes found for stack ${stack} (project ${STACK_PROJECT})"

  timestamp="$(date -u +"%Y%m%dT%H%M%SZ")"
  backup_dir="${backup_root}/${stack}-${timestamp}"
  ensure_dir "${backup_dir}"

  write_metadata "${stack}" "${backup_dir}"
  write_volume_manifest "${backup_dir}" "${volumes[@]}"

  if [[ "${STACK_BACKUP_COMPOSE_DIR}" -eq 1 ]]; then
    backup_compose_dir "${STACK_COMPOSE_DIR}" "${backup_dir}"
  fi

  for volume_name in "${volumes[@]}"; do
    log "Backing up ${stack} volume ${volume_name}"
    backup_single_volume "${volume_name}" "${backup_dir}"
  done

  log "Backup complete: ${backup_dir}"
}

restore_from_backup_dir() {
  local stack="$1"
  local input_dir="$2"
  local volume_name=""

  resolve_stack_metadata "${stack}"
  load_metadata "${input_dir}"
  read_volume_manifest "${input_dir}"
  ((${#MANIFEST_VOLUMES[@]} > 0)) || die "No volumes recorded in ${input_dir}/volumes.txt"

  stop_stack_if_possible "${STACK_COMPOSE_DIR}" "${STACK_PROJECT}"

  if [[ "${STACK_BACKUP_COMPOSE_DIR}" -eq 1 ]]; then
    restore_compose_dir "${STACK_COMPOSE_DIR}" "${input_dir}"
  fi

  for volume_name in "${MANIFEST_VOLUMES[@]}"; do
    log "Restoring ${stack} volume ${volume_name}"
    restore_single_volume "${volume_name}" "${input_dir}"
  done

  start_stack_if_possible "${STACK_COMPOSE_DIR}"
  log "Restore complete from ${input_dir}"
}

backup_local_compose() {
  local backup_root="$1"
  backup_single_stack "deployment-kong" "${backup_root}"
  backup_single_stack "observability" "${backup_root}"
}

inspect_local_compose() {
  inspect_single_stack "deployment-kong"
  printf '\n'
  inspect_single_stack "observability"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    inspect|backup|restore)
      ACTION="$1"
      ;;
    deployment-kong|observability|azure-host-kong|local-minikube|local-compose)
      STACK="$1"
      ;;
    --output-dir)
      shift
      [[ $# -gt 0 ]] || die "Missing value for --output-dir"
      OUTPUT_DIR="$1"
      ;;
    --input-dir)
      shift
      [[ $# -gt 0 ]] || die "Missing value for --input-dir"
      INPUT_DIR="$1"
      ;;
    --force)
      FORCE_RESTORE=1
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

[[ -n "${STACK}" ]] || die "You must select a stack"

if [[ "${STACK}" == "local-minikube" ]]; then
  require_command kubectl tar
else
  require_command docker tar
fi

case "${ACTION}" in
  inspect)
    if [[ "${STACK}" == "local-compose" ]]; then
      inspect_local_compose
    elif [[ "${STACK}" == "local-minikube" ]]; then
      inspect_local_minikube
    else
      inspect_single_stack "${STACK}"
    fi
    ;;
  backup)
    backup_root="${OUTPUT_DIR:-${DEFAULT_BACKUP_ROOT}}"
    ensure_dir "${backup_root}"
    if [[ "${STACK}" == "local-compose" ]]; then
      backup_local_compose "${backup_root}"
    elif [[ "${STACK}" == "local-minikube" ]]; then
      backup_local_minikube "${backup_root}"
    else
      backup_single_stack "${STACK}" "${backup_root}"
    fi
    ;;
  restore)
    [[ -n "${INPUT_DIR}" ]] || die "restore requires --input-dir"
    [[ "${STACK}" != "local-compose" ]] || die "restore does not support the local-compose alias; restore each backup directory individually"
    if [[ "${STACK}" == "local-minikube" ]]; then
      restore_local_minikube "${INPUT_DIR}"
    else
      restore_from_backup_dir "${STACK}" "${INPUT_DIR}"
    fi
    ;;
esac
