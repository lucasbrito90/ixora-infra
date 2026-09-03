#!/usr/bin/env bash
# ============================================================
# Ixora Observability — Single Volume Restore (staging)
# Phase 8.8.7 — Staging backup automation
#
# Restores ONE observability volume from a local tarball:
#   stop service → extract tarball into volume → start service → health check
#
# USAGE (on the observability host):
#   cd /opt/ixora-observability
#   ./scripts/restore-observability-volume.sh prometheus
#   ./scripts/restore-observability-volume.sh loki /opt/ixora-observability/backups/loki_data-20260829-030000.tar.gz
#
# If no tarball path is given, the most recent backup for that service's
# volume is selected automatically.
#
# ENVIRONMENT:
#   IXORA_DEPLOY_PATH   Deploy root (default: /opt/ixora-observability)
#   IXORA_BACKUP_DIR    Backup directory (default: $IXORA_DEPLOY_PATH/backups)
#   HEALTH_CHECK_RETRIES  Health poll attempts (default: 12)
#   HEALTH_CHECK_INTERVAL Seconds between polls (default: 5)
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DEPLOY_PATH="${IXORA_DEPLOY_PATH:-/opt/ixora-observability}"
COMPOSE_DIR="${IXORA_COMPOSE_DIR:-${DEPLOY_PATH}/collector}"
BACKUP_DIR="${IXORA_BACKUP_DIR:-${DEPLOY_PATH}/backups}"
HEALTH_RETRIES="${HEALTH_CHECK_RETRIES:-12}"
HEALTH_INTERVAL="${HEALTH_CHECK_INTERVAL:-5}"
ALPINE_IMAGE="${IXORA_BACKUP_ALPINE_IMAGE:-alpine:3.20}"

declare -A SERVICE_VOLUME=(
  [prometheus]=prometheus_data
  [loki]=loki_data
  [tempo]=tempo_data
  [grafana]=grafana_data
)

declare -A SERVICE_HEALTH_URL=(
  [prometheus]="http://127.0.0.1:${PROMETHEUS_PORT:-9090}/-/ready"
  [loki]="http://127.0.0.1:${LOKI_PORT:-3100}/ready"
  [tempo]="http://127.0.0.1:${TEMPO_PORT:-3200}/ready"
  [grafana]="http://127.0.0.1:${GRAFANA_PORT:-3000}/api/health"
)

log() {
  echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] $*" >&2
}

resolve_compose_volume() {
  local volume_key="$1"
  local match
  match="$(docker volume ls -q | grep "_${volume_key}$" | head -1 || true)"
  if [[ -z "${match}" ]]; then
    log "ERROR: could not resolve Docker volume for compose key '${volume_key}'"
    return 1
  fi
  echo "${match}"
}

usage() {
  sed -n '3,22p' "$0" | sed 's/^# \{0,1\}//'
  cat <<EOF

Usage:
  $0 <service> [tarball-path]

Services: prometheus | loki | tempo | grafana

Examples:
  $0 prometheus
  $0 loki ${BACKUP_DIR}/loki_data-20260829-030000.tar.gz
EOF
}

list_available_backups() {
  local volume="$1"
  shopt -s nullglob
  local -a files=( "${BACKUP_DIR}/${volume}-"*.tar.gz )
  shopt -u nullglob

  if (( ${#files[@]} == 0 )); then
    log "No backups found matching ${BACKUP_DIR}/${volume}-*.tar.gz"
    return 1
  fi

  log "Available backups for ${volume}:"
  ls -1t "${BACKUP_DIR}/${volume}-"*.tar.gz
}

resolve_tarball() {
  local volume="$1"
  local explicit="${2:-}"

  if [[ -n "${explicit}" ]]; then
    if [[ ! -f "${explicit}" ]]; then
      log "ERROR: tarball not found: ${explicit}"
      list_available_backups "${volume}" || true
      return 1
    fi
    echo "${explicit}"
    return 0
  fi

  shopt -s nullglob
  local -a files=( "${BACKUP_DIR}/${volume}-"*.tar.gz )
  shopt -u nullglob

  if (( ${#files[@]} == 0 )); then
    log "ERROR: no tarball found for volume ${volume} in ${BACKUP_DIR}"
    return 1
  fi

  local latest
  latest="$(ls -1t "${BACKUP_DIR}/${volume}-"*.tar.gz | head -1)"
  log "No tarball specified — using latest: ${latest}"
  echo "${latest}"
}

wait_for_health() {
  local service="$1"
  local url="${SERVICE_HEALTH_URL[$service]}"
  local attempt=1

  log "[${service}] Waiting for health check: ${url}"

  while (( attempt <= HEALTH_RETRIES )); do
    if curl -sf --max-time 5 "${url}" >/dev/null 2>&1; then
      log "[${service}] Health check passed (attempt ${attempt}/${HEALTH_RETRIES})"
      return 0
    fi
    log "[${service}] Health check not ready (attempt ${attempt}/${HEALTH_RETRIES}) — retrying in ${HEALTH_INTERVAL}s"
    sleep "${HEALTH_INTERVAL}"
    attempt=$(( attempt + 1 ))
  done

  log "ERROR [${service}] Health check failed after ${HEALTH_RETRIES} attempts: ${url}"
  return 1
}

restore_service() {
  local service="$1"
  local tarball="$2"
  local volume="${SERVICE_VOLUME[$service]}"
  local full_volume
  local stopped=0
  local tarball_base
  tarball_base="$(basename "${tarball}")"

  full_volume="$(resolve_compose_volume "${volume}")" || return 1

  ensure_service_running() {
    if (( stopped )); then
      log "[${service}] Ensuring service is running after restore step..."
      if ! docker compose -f "${COMPOSE_DIR}/docker-compose.yml" start "${service}"; then
        log "ERROR [${service}] docker compose start failed — manual intervention required"
      fi
    fi
  }

  log "────────────────────────────────────────────────"
  log "[${service}] Starting restore from ${tarball}"
  log "[${service}] Volume: ${volume}"

  log "[${service}] Stopping service..."
  if ! docker compose -f "${COMPOSE_DIR}/docker-compose.yml" stop "${service}"; then
    log "ERROR [${service}] docker compose stop failed — aborting restore"
    return 1
  fi
  stopped=1
  trap ensure_service_running RETURN

  log "[${service}] Extracting ${tarball_base} into volume ${full_volume}..."
  if ! docker run --rm \
    -v "${full_volume}:/volume" \
    -v "${BACKUP_DIR}:/backup:ro" \
    "${ALPINE_IMAGE}" sh -c "
      set -eu
      rm -rf /volume/* /volume/.[!.]* /volume/..?* 2>/dev/null || true
      tar xzf \"/backup/${tarball_base}\" -C /volume
    "; then
    log "ERROR [${service}] tar extract failed — service will still be restarted"
    trap - RETURN
    ensure_service_running
    return 1
  fi

  trap - RETURN
  ensure_service_running
  stopped=0

  if ! wait_for_health "${service}"; then
    log "ERROR [${service}] Restore extracted but health check failed — verify manually"
    return 1
  fi

  log "[${service}] Restore complete"
  return 0
}

# ── Argument parsing ───────────────────────────────────────────────────────────

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" || $# -lt 1 ]]; then
  usage
  [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && exit 0 || exit 1
fi

SERVICE="$1"
TARBALL_ARG="${2:-}"

if [[ -z "${SERVICE_VOLUME[$SERVICE]+x}" ]]; then
  log "ERROR: unknown service '${SERVICE}' — expected: prometheus | loki | tempo | grafana"
  exit 1
fi

if [[ ! -f "${COMPOSE_DIR}/docker-compose.yml" ]]; then
  log "ERROR: docker-compose.yml not found at ${COMPOSE_DIR}"
  exit 1
fi

VOLUME="${SERVICE_VOLUME[$SERVICE]}"

TARBALL="$(resolve_tarball "${VOLUME}" "${TARBALL_ARG}")" || exit 1

log "Ixora observability volume restore"
log "Service     : ${SERVICE}"
log "Volume      : ${VOLUME}"
log "Tarball     : ${TARBALL}"
log "Compose dir : ${COMPOSE_DIR}"

cd "${COMPOSE_DIR}"

if ! restore_service "${SERVICE}" "${TARBALL}"; then
  log "Restore failed for ${SERVICE}"
  exit 1
fi

log "────────────────────────────────────────────────"
log "Restore succeeded. Verify data continuity in Grafana (backup-strategy.md §4.1 step 5)."
