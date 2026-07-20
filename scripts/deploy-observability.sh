#!/usr/bin/env bash
# ============================================================
# Ixora Observability — Docker Compose deployment
# Phase 8.8.5 — Observability Infrastructure Provisioning
#
# Executes the existing collector/docker-compose.yml stack.
# Idempotent — safe to re-run for upgrades and config changes.
#
# Usage (on observability host):
#   cd /opt/ixora-observability
#   ./scripts/deploy-observability.sh
#
# Environment:
#   IXORA_DEPLOY_PATH  — default /opt/ixora-observability
#   SKIP_GRAFANA_VALIDATE — set to 1 to skip validate.sh
#   GF_ADMIN_PASSWORD  — required for Grafana validation (not logged)
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEPLOY_PATH="${IXORA_DEPLOY_PATH:-/opt/ixora-observability}"
COLLECTOR_DIR="${DEPLOY_PATH}/collector"
ENV_FILE="${COLLECTOR_DIR}/.env"
MARKER="/etc/ixora-observability-host"

PASS=0
FAIL=0

green()  { printf '\033[0;32m✓ %s\033[0m\n' "$*"; ((PASS++)) || true; }
red()    { printf '\033[0;31m✗ %s\033[0m\n' "$*"; ((FAIL++)) || true; }
yellow() { printf '\033[0;33m  %s\033[0m\n' "$*"; }

step() {
  echo ""
  echo "── $*"
}

fail_or_exit() {
  red "$1"
  exit 1
}

step "Preflight"

if [[ -f "${MARKER}" ]]; then
  green "Observability host marker present"
else
  yellow "Marker ${MARKER} not found — continuing (manual/dev host?)"
fi

command -v docker >/dev/null 2>&1 || fail_or_exit "docker not installed"
command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1 || fail_or_exit "docker compose v2 not available"

green "Docker and Compose available"

[[ -d "${COLLECTOR_DIR}" ]] || fail_or_exit "Missing ${COLLECTOR_DIR}"
[[ -f "${COLLECTOR_DIR}/docker-compose.yml" ]] || fail_or_exit "Missing docker-compose.yml"

green "Collector directory present"

[[ -f "${ENV_FILE}" ]] || fail_or_exit "Missing ${ENV_FILE} — run scripts/bootstrap-collector-env.sh first"
[[ "$(stat -c '%a' "${ENV_FILE}")" == "600" ]] || fail_or_exit "${ENV_FILE} must be chmod 600"

green "collector/.env exists with mode 600"

if grep -q 'REPLACE_WITH_STRONG' "${ENV_FILE}"; then
  fail_or_exit "Placeholder secrets remain in ${ENV_FILE}"
fi

if grep -q '^GF_SERVER_ROOT_URL=http://localhost' "${ENV_FILE}"; then
  fail_or_exit "GF_SERVER_ROOT_URL still points to localhost"
fi

if grep -q '^GF_SECURITY_COOKIE_SECURE=false' "${ENV_FILE}"; then
  fail_or_exit "GF_SECURITY_COOKIE_SECURE must be true on staging"
fi

green "No placeholder secrets detected"

step "Docker Compose validation"

cd "${COLLECTOR_DIR}"
docker compose config >/dev/null || fail_or_exit "docker compose config failed"
green "docker compose config OK"

step "Pull images"

docker compose pull
green "Images pulled"

step "Start services"

docker compose up -d
green "docker compose up -d completed"

step "Wait for health endpoints"

wait_http() {
  local url="$1"
  local label="$2"
  local attempts="${3:-30}"
  local i
  for ((i = 1; i <= attempts; i++)); do
    if curl -sf "${url}" >/dev/null 2>&1; then
      green "${label} healthy (${url})"
      return 0
    fi
    sleep 2
  done
  red "${label} not healthy after ${attempts} attempts (${url})"
  return 1
}

wait_http "http://127.0.0.1:13133/health" "Collector" 30 || true
wait_http "http://127.0.0.1:9090/-/healthy" "Prometheus" 30 || true
wait_http "http://127.0.0.1:3100/ready" "Loki" 30 || true
wait_http "http://127.0.0.1:3200/ready" "Tempo" 30 || true
wait_http "http://127.0.0.1:3000/api/health" "Grafana" 45 || true

step "Service status"

docker compose ps

EXPECTED=(ixora-otel-collector ixora-prometheus ixora-loki ixora-tempo ixora-grafana)
for svc in "${EXPECTED[@]}"; do
  if docker compose ps --format json 2>/dev/null | grep -q "\"Name\":\"${svc}\"" || docker compose ps | grep -q "${svc}"; then
    green "Container ${svc} present"
  else
    red "Container ${svc} missing"
  fi
done

step "Volume persistence check"

for vol in prometheus_data loki_data tempo_data grafana_data; do
  if docker volume inspect "collector_${vol}" >/dev/null 2>&1 || docker volume inspect "${vol}" >/dev/null 2>&1; then
    green "Volume ${vol} exists"
  else
    yellow "Volume ${vol} name may differ — inspect: docker volume ls"
  fi
done

step "Grafana validation (optional)"

if [[ "${SKIP_GRAFANA_VALIDATE:-0}" == "1" ]]; then
  yellow "Skipping validate.sh (SKIP_GRAFANA_VALIDATE=1)"
elif [[ -z "${GF_ADMIN_PASSWORD:-}" ]]; then
  yellow "GF_ADMIN_PASSWORD not set in shell — skipping validate.sh"
elif [[ -x "${COLLECTOR_DIR}/grafana/validate.sh" ]]; then
  if (cd "${COLLECTOR_DIR}" && GF_ADMIN_PASSWORD="${GF_ADMIN_PASSWORD}" ./grafana/validate.sh); then
    green "Grafana validate.sh passed"
  else
    red "Grafana validate.sh failed"
  fi
else
  yellow "validate.sh not found or not executable"
fi

step "Enable systemd unit (if present)"

if systemctl list-unit-files ixora-observability.service >/dev/null 2>&1; then
  systemctl enable ixora-observability.service >/dev/null 2>&1 || true
  green "ixora-observability.service enabled for reboot"
fi

echo ""
echo "────────────────────────────────────────────────"
if [[ "${FAIL}" -eq 0 ]]; then
  green "Deployment summary: ${PASS} checks passed"
  echo ""
  echo "Grafana (via Caddy): check GF_SERVER_ROOT_URL in ${ENV_FILE}"
  echo "OTLP HTTP (via Caddy): https://otel-staging.ixora-app.app (after DNS + TLS)"
  echo "Internal only: Prometheus :9090, Loki :3100, Tempo :3200, Grafana :3000 on 127.0.0.1"
  exit 0
else
  red "Deployment completed with ${FAIL} failure(s), ${PASS} passed"
  exit 1
fi
