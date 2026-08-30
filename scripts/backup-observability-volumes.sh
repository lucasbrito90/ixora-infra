#!/usr/bin/env bash
# ============================================================
# Ixora Observability — Volume Backup (staging)
# Phase 8.8.7 — Staging backup automation
#
# Backs up the four observability Docker volumes sequentially:
#   prometheus_data, loki_data, tempo_data, grafana_data
#
# Each service is stopped individually, tarred, restarted, then the
# script moves to the next service — staging stays up as much as possible.
#
# Retention: keeps the last 4 tarballs per volume (≈4 weekly generations;
# enough to recover from a bad deploy or operator error without unbounded
# disk growth on the staging Droplet).
#
# USAGE (on the observability host):
#   cd /opt/ixora-observability
#   ./scripts/backup-observability-volumes.sh
#
# LOCAL / OVERRIDE:
#   IXORA_DEPLOY_PATH=/path/to/repo \
#   IXORA_BACKUP_DIR=/tmp/ixora-backups \
#   ./scripts/backup-observability-volumes.sh
#
# ENVIRONMENT:
#   IXORA_DEPLOY_PATH   Deploy root (default: /opt/ixora-observability)
#   IXORA_BACKUP_DIR    Backup output dir (default: $IXORA_DEPLOY_PATH/backups)
#   IXORA_RETENTION     Tarballs to keep per volume (default: 4)
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DEPLOY_PATH="${IXORA_DEPLOY_PATH:-/opt/ixora-observability}"
COMPOSE_DIR="${IXORA_COMPOSE_DIR:-${DEPLOY_PATH}/collector}"
BACKUP_DIR="${IXORA_BACKUP_DIR:-${DEPLOY_PATH}/backups}"
RETENTION="${IXORA_RETENTION:-4}"

# service:volume pairs — processed in order (see backup-strategy.md §3).
SERVICES=(
  "prometheus:prometheus_data"
  "loki:loki_data"
  "tempo:tempo_data"
  "grafana:grafana_data"
)

TIMESTAMP="$(date -u '+%Y%m%d-%H%M%S')"

ALPINE_IMAGE="${IXORA_BACKUP_ALPINE_IMAGE:-alpine:3.20}"

log() {
  echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] $*" >&2
}

# Resolve the Docker-managed volume name (e.g. collector_prometheus_data) from the
# compose volume key (prometheus_data). Uses suffix match so it works regardless
# of compose project name prefix.
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
  sed -n '3,28p' "$0" | sed 's/^# \{0,1\}//'
  cat <<EOF

Environment overrides:
  IXORA_DEPLOY_PATH   (default: /opt/ixora-observability)
  IXORA_BACKUP_DIR    (default: \$IXORA_DEPLOY_PATH/backups)
  IXORA_RETENTION     (default: 4)
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ ! -f "${COMPOSE_DIR}/docker-compose.yml" ]]; then
  log "ERROR: docker-compose.yml not found at ${COMPOSE_DIR}"
  exit 1
fi

mkdir -p "${BACKUP_DIR}"

# ── Disk space ────────────────────────────────────────────────────────────────

check_disk_space() {
  local volume="$1"
  local full_volume avail_kb used_bytes required_kb

  full_volume="$(resolve_compose_volume "${volume}")" || return 1

  avail_kb="$(df -k "${BACKUP_DIR}" | awk 'NR==2 {print $4}')"
  used_bytes="$(
    docker run --rm \
      -v "${full_volume}:/volume:ro" \
      "${ALPINE_IMAGE}" du -sb /volume 2>/dev/null | awk '{print $1}' || echo 0
  )"

  # Worst case: tarball ≈ volume size (TSDB/WAL compress poorly). Add 10% + 1 MiB headroom.
  required_kb="$(( used_bytes / 1024 + used_bytes / 10240 + 1024 ))"

  if (( avail_kb < required_kb )); then
    log "ERROR: insufficient disk space in ${BACKUP_DIR}"
    log "       need ~${required_kb} KiB free, have ${avail_kb} KiB"
    return 1
  fi

  log "Disk space OK for ${volume} (need ~${required_kb} KiB, have ${avail_kb} KiB free)"
  return 0
}

# ── Retention ─────────────────────────────────────────────────────────────────

rotate_retention() {
  local volume="$1"
  local -a files=()
  local file

  shopt -s nullglob
  for file in "${BACKUP_DIR}/${volume}-"*.tar.gz; do
    files+=("$file")
  done
  shopt -u nullglob

  if (( ${#files[@]} <= RETENTION )); then
    log "Retention: ${#files[@]} tarball(s) for ${volume} (limit ${RETENTION}) — nothing to prune"
    return 0
  fi

  # Newest first (GNU sort -r on mtime via ls -t).
  mapfile -t files < <(ls -1t "${BACKUP_DIR}/${volume}-"*.tar.gz 2>/dev/null || true)

  local i
  for (( i = RETENTION; i < ${#files[@]}; i++ )); do
    log "Retention: removing old backup ${files[$i]}"
    rm -f "${files[$i]}"
  done
}

# ── Per-service backup ────────────────────────────────────────────────────────

backup_one_service() {
  local service="$1"
  local volume="$2"
  local full_volume
  local archive_name="${volume}-${TIMESTAMP}.tar.gz"
  local archive_path="${BACKUP_DIR}/${archive_name}"
  local stopped=0

  full_volume="$(resolve_compose_volume "${volume}")" || return 1

  ensure_service_running() {
    if (( stopped )); then
      log "[${service}] Ensuring service is running after backup step..."
      if ! docker compose -f "${COMPOSE_DIR}/docker-compose.yml" start "${service}"; then
        log "ERROR [${service}] docker compose start failed — manual intervention required"
      fi
    fi
  }

  log "────────────────────────────────────────────────"
  log "[${service}] Starting backup (volume: ${volume})"

  log "[${service}] Stopping service..."
  if ! docker compose -f "${COMPOSE_DIR}/docker-compose.yml" stop "${service}"; then
    log "ERROR [${service}] docker compose stop failed — skipping this service"
    return 1
  fi
  stopped=1
  trap ensure_service_running RETURN

  if ! check_disk_space "${volume}"; then
    log "ERROR [${service}] disk space check failed — skipping tar (retention unchanged)"
    trap - RETURN
    ensure_service_running
    return 1
  fi

  log "[${service}] Creating tarball ${archive_name} (volume: ${full_volume})..."
  if ! docker run --rm \
    -v "${full_volume}:/volume:ro" \
    -v "${BACKUP_DIR}:/backup" \
    "${ALPINE_IMAGE}" tar czf "/backup/${archive_name}" -C /volume .; then
    log "ERROR [${service}] tar failed — removing partial archive if present"
    rm -f "${archive_path}"
    trap - RETURN
    ensure_service_running
    return 1
  fi

  trap - RETURN
  ensure_service_running
  stopped=0

  if [[ ! -f "${archive_path}" ]]; then
    log "ERROR [${service}] tarball missing after tar command — retention unchanged"
    return 1
  fi

  log "[${service}] Backup written: ${archive_path} ($(du -h "${archive_path}" | awk '{print $1}'))"
  rotate_retention "${volume}"
  log "[${service}] Backup complete"
  return 0
}

# ── Main ──────────────────────────────────────────────────────────────────────

log "Ixora observability volume backup"
log "Compose dir : ${COMPOSE_DIR}"
log "Backup dir  : ${BACKUP_DIR}"
log "Retention   : ${RETENTION} tarball(s) per volume"
log "Timestamp   : ${TIMESTAMP}"

cd "${COMPOSE_DIR}"

failed=()
for entry in "${SERVICES[@]}"; do
  IFS=: read -r service volume <<< "${entry}"
  if ! backup_one_service "${service}" "${volume}"; then
    failed+=("${service}")
  fi
done

log "────────────────────────────────────────────────"
if (( ${#failed[@]} == 0 )); then
  log "All ${#SERVICES[@]} volume backups succeeded."
  exit 0
fi

log "WARNING: backup failed for: ${failed[*]}"
log "Other services were backed up independently; check logs above."
exit 1
