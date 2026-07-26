#!/usr/bin/env bash
# ============================================================
# Ixora Observability - Docker Compose deployment
# Phase 8.8.5 - Observability Infrastructure Provisioning
# Phase 8.8.6 - release ref support (IXORA_GIT_REF)
#
# MODES:
#   Remote (from operator machine):
#     ./scripts/deploy-observability.sh --host 143.198.36.226 --user root
#     Rsyncs repository source to the Droplet, then SSHes in to run the
#     local deployment steps. Never copies .git, state, or secret files.
#
#   Local (on observability host directly):
#     cd /opt/ixora-observability
#     ./scripts/deploy-observability.sh
#
# Environment variables:
#   IXORA_DEPLOY_PATH  - default /opt/ixora-observability
#   IXORA_GIT_REF      - optional Git tag/branch to checkout before deploy
#   SKIP_GRAFANA_VALIDATE - set to 1 to skip validate.sh
#   GF_ADMIN_PASSWORD  - required for Grafana validation (not logged)
#   SKIP_IMAGE_PULL    - set to 1 to skip docker compose pull (faster re-runs)
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── Argument parsing ──────────────────────────────────────────────────────

REMOTE_HOST=""
REMOTE_USER="root"
SSH_KEY_ARG=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)     REMOTE_HOST="$2";   shift 2 ;;
    --user)     REMOTE_USER="$2";   shift 2 ;;
    --ssh-key)  SSH_KEY_ARG="-i $2"; shift 2 ;;
    --dry-run)  DRY_RUN=1;          shift ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      printf 'Usage: %s [--host <ip> --user <user>] [--ssh-key /path/to/key] [--dry-run]\n' "$0" >&2
      exit 1
      ;;
  esac
done

# ── Remote mode: rsync + SSH ──────────────────────────────────────────────

if [[ -n "${REMOTE_HOST}" ]]; then
  SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=15 -o BatchMode=yes"
  SSH_CMD="ssh ${SSH_OPTS} ${SSH_KEY_ARG} ${REMOTE_USER}@${REMOTE_HOST}"
  DEPLOY_PATH="${IXORA_DEPLOY_PATH:-/opt/ixora-observability}"

  printf '\033[0;34m[INFO] Remote mode: %s@%s -> %s\033[0m\n' "${REMOTE_USER}" "${REMOTE_HOST}" "${DEPLOY_PATH}"

  # ── Verify SSH connectivity ────────────────────────────────────────────
  printf '\033[0;34m[INFO] Checking SSH connectivity...\033[0m\n'
  if ! ${SSH_CMD} -- 'echo ok' >/dev/null 2>&1; then
    printf '\033[0;31m[FAIL] SSH connection failed to %s@%s\033[0m\n' "${REMOTE_USER}" "${REMOTE_HOST}" >&2
    exit 1
  fi
  printf '\033[0;32m[OK]   SSH connection verified\033[0m\n'

  # ── Verify Docker and Caddy ────────────────────────────────────────────
  if ! ${SSH_CMD} -- 'command -v docker >/dev/null' 2>/dev/null; then
    printf '\033[0;31m[FAIL] Docker not installed on remote. Run: ./scripts/repair-observability-host.sh --host %s --user %s\033[0m\n' \
      "${REMOTE_HOST}" "${REMOTE_USER}" >&2
    exit 1
  fi
  printf '\033[0;32m[OK]   Docker present on remote\033[0m\n'

  if ! ${SSH_CMD} -- 'systemctl is-active caddy >/dev/null 2>&1' 2>/dev/null; then
    printf '\033[0;33m[WARN] Caddy is not active on remote - run repair-observability-host.sh first\033[0m\n'
  else
    printf '\033[0;32m[OK]   Caddy active on remote\033[0m\n'
  fi

  # ── Verify local collector/ directory ─────────────────────────────────
  if [[ ! -d "${REPO_ROOT}/collector" ]]; then
    printf '\033[0;31m[FAIL] Local collector/ directory not found at %s\033[0m\n' "${REPO_ROOT}/collector" >&2
    exit 1
  fi
  if [[ ! -f "${REPO_ROOT}/collector/docker-compose.yml" ]]; then
    printf '\033[0;31m[FAIL] collector/docker-compose.yml not found\033[0m\n' >&2
    exit 1
  fi
  printf '\033[0;32m[OK]   Local collector/ directory verified\033[0m\n'

  # ── Create deploy path on remote ──────────────────────────────────────
  ${SSH_CMD} -- "mkdir -p ${DEPLOY_PATH}/collector && chmod 755 ${DEPLOY_PATH}"

  # ── rsync collector/ to remote ─────────────────────────────────────────
  printf '\033[0;34m[INFO] Syncing collector/ to %s:%s/collector/...\033[0m\n' "${REMOTE_HOST}" "${DEPLOY_PATH}"

  RSYNC_EXCLUDE=(
    "--exclude=.git"
    "--exclude=.git/"
    "--exclude=*.tfstate"
    "--exclude=*.tfstate.*"
    "--exclude=*.tfvars"
    "--exclude=plan.json"
    "--exclude=tfplan"
    "--exclude=*.tfplan"
    "--exclude=.env"
    "--exclude=.DS_Store"
    "--exclude=__pycache__/"
    "--exclude=node_modules/"
  )

  RSYNC_SSH="ssh ${SSH_OPTS} ${SSH_KEY_ARG}"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    rsync -avzn \
      "${RSYNC_EXCLUDE[@]}" \
      --protect-args \
      -e "${RSYNC_SSH}" \
      "${REPO_ROOT}/collector/" \
      "${REMOTE_USER}@${REMOTE_HOST}:${DEPLOY_PATH}/collector/"
    printf '\033[0;33m[DRY-RUN] rsync shown above - no files transferred\033[0m\n'
  else
    rsync -avz \
      "${RSYNC_EXCLUDE[@]}" \
      --protect-args \
      --no-perms \
      -e "${RSYNC_SSH}" \
      "${REPO_ROOT}/collector/" \
      "${REMOTE_USER}@${REMOTE_HOST}:${DEPLOY_PATH}/collector/"
    printf '\033[0;32m[OK]   collector/ synced to remote\033[0m\n'
  fi

  # Also sync scripts/ for remote deploy script access
  printf '\033[0;34m[INFO] Syncing scripts/ to remote...\033[0m\n'
  if [[ "${DRY_RUN}" -eq 0 ]]; then
    rsync -avz \
      --exclude='.git' \
      --protect-args \
      --no-perms \
      -e "${RSYNC_SSH}" \
      "${REPO_ROOT}/scripts/" \
      "${REMOTE_USER}@${REMOTE_HOST}:${DEPLOY_PATH}/scripts/"
    ${SSH_CMD} -- "chmod +x ${DEPLOY_PATH}/scripts/*.sh 2>/dev/null || true"
    printf '\033[0;32m[OK]   scripts/ synced to remote\033[0m\n'
  fi

  # ── Fix permissions ────────────────────────────────────────────────────
  if [[ "${DRY_RUN}" -eq 0 ]]; then
    ${SSH_CMD} -- "chown -R root:root ${DEPLOY_PATH}/collector && chmod -R o-w ${DEPLOY_PATH}/collector"
    # Preserve .env permissions if it exists
    ${SSH_CMD} -- "test -f ${DEPLOY_PATH}/collector/.env && chmod 600 ${DEPLOY_PATH}/collector/.env || true"
    printf '\033[0;32m[OK]   Permissions set on remote\033[0m\n'
  fi

  # ── Run local deploy on remote via SSH ────────────────────────────────
  printf '\033[0;34m[INFO] Running deploy script on remote...\033[0m\n'
  if [[ "${DRY_RUN}" -eq 0 ]]; then
    REMOTE_ENV_VARS=""
    [[ -n "${IXORA_GIT_REF:-}" ]] && REMOTE_ENV_VARS="${REMOTE_ENV_VARS} IXORA_GIT_REF=${IXORA_GIT_REF}"
    [[ "${SKIP_GRAFANA_VALIDATE:-0}" == "1" ]] && REMOTE_ENV_VARS="${REMOTE_ENV_VARS} SKIP_GRAFANA_VALIDATE=1"
    [[ "${SKIP_IMAGE_PULL:-0}" == "1" ]] && REMOTE_ENV_VARS="${REMOTE_ENV_VARS} SKIP_IMAGE_PULL=1"

    ${SSH_CMD} -- "cd ${DEPLOY_PATH} && env IXORA_DEPLOY_PATH=${DEPLOY_PATH} ${REMOTE_ENV_VARS} ./scripts/deploy-observability.sh"
  else
    printf '\033[0;33m[DRY-RUN] Would run: ssh %s@%s "cd %s && ./scripts/deploy-observability.sh"\033[0m\n' \
      "${REMOTE_USER}" "${REMOTE_HOST}" "${DEPLOY_PATH}"
  fi

  exit $?
fi

# ── Local mode: run on the observability host directly ───────────────────

DEPLOY_PATH="${IXORA_DEPLOY_PATH:-/opt/ixora-observability}"
COLLECTOR_DIR="${DEPLOY_PATH}/collector"
ENV_FILE="${COLLECTOR_DIR}/.env"
MARKER="/etc/ixora-observability-host"

PASS=0
FAIL=0

green()  { printf '\033[0;32m[OK]   %s\033[0m\n' "$*"; ((PASS++)) || true; }
red()    { printf '\033[0;31m[FAIL] %s\033[0m\n' "$*"; ((FAIL++)) || true; }
yellow() { printf '\033[0;33m[WARN] %s\033[0m\n' "$*"; }

step() {
  echo ""
  echo "== $*"
}

fail_or_exit() {
  red "$1"
  exit 1
}

step "Preflight"

if [[ -f "${MARKER}" ]]; then
  green "Observability host marker present"
else
  yellow "Marker ${MARKER} not found - continuing (manual/dev host?)"
fi

command -v docker >/dev/null 2>&1 || fail_or_exit "docker not installed"
docker compose version >/dev/null 2>&1 || fail_or_exit "docker compose v2 not available"

green "Docker and Compose available"

[[ -d "${COLLECTOR_DIR}" ]] || fail_or_exit "Missing ${COLLECTOR_DIR}"
[[ -f "${COLLECTOR_DIR}/docker-compose.yml" ]] || fail_or_exit "Missing docker-compose.yml"

green "Collector directory present"

[[ -f "${ENV_FILE}" ]] || fail_or_exit "Missing ${ENV_FILE} - run scripts/bootstrap-collector-env.sh first"
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

step "Release ref (optional)"

if [[ -n "${IXORA_GIT_REF:-}" ]]; then
  if [[ -d "${DEPLOY_PATH}/.git" ]]; then
    cd "${DEPLOY_PATH}"
    git fetch --tags origin 2>/dev/null || yellow "git fetch failed - continuing with local refs"
    git checkout "${IXORA_GIT_REF}" || fail_or_exit "git checkout ${IXORA_GIT_REF} failed"
    green "Checked out ${IXORA_GIT_REF}"
  else
    fail_or_exit "IXORA_GIT_REF set but ${DEPLOY_PATH} is not a git repository"
  fi
fi

step "Docker Compose validation"

cd "${COLLECTOR_DIR}"
docker compose config >/dev/null || fail_or_exit "docker compose config failed"
green "docker compose config OK"

if [[ "${SKIP_IMAGE_PULL:-0}" != "1" ]]; then
  step "Pull images"
  docker compose pull
  green "Images pulled"
else
  yellow "Image pull skipped (SKIP_IMAGE_PULL=1)"
fi

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

wait_http "http://127.0.0.1:13133/health" "Collector (health_check extension)" 30 || true
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

step "Port binding verification"

for port in 13133 9090 3100 3200 3000; do
  if ss -lntp 2>/dev/null | grep -q ":${port} "; then
    BINDING="$(ss -lntp 2>/dev/null | grep ":${port} " | awk '{print $4}' | head -1)"
    if echo "${BINDING}" | grep -q '127.0.0.1'; then
      green "Port ${port} bound to 127.0.0.1 (OK)"
    else
      yellow "Port ${port} binding: ${BINDING} - verify not public"
    fi
  else
    yellow "Port ${port} not yet listening"
  fi
done

step "Volume persistence check"

for vol in prometheus_data loki_data tempo_data grafana_data; do
  if docker volume inspect "collector_${vol}" >/dev/null 2>&1 || docker volume inspect "${vol}" >/dev/null 2>&1; then
    green "Volume ${vol} exists"
  else
    yellow "Volume ${vol} name may differ - inspect: docker volume ls"
  fi
done

step "Grafana validation (optional)"

if [[ "${SKIP_GRAFANA_VALIDATE:-0}" == "1" ]]; then
  yellow "Skipping validate.sh (SKIP_GRAFANA_VALIDATE=1)"
elif [[ -z "${GF_ADMIN_PASSWORD:-}" ]]; then
  yellow "GF_ADMIN_PASSWORD not set in shell - skipping validate.sh"
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

step "Caddy public connectivity"

if systemctl is-active caddy >/dev/null 2>&1; then
  green "Caddy service active"
  if ss -lntp 2>/dev/null | grep -q ':443 '; then
    green "Caddy listening on port 443"
  else
    yellow "Port 443 not listening yet - Caddy may still be starting"
  fi
else
  red "Caddy is not active"
fi

echo ""
echo "────────────────────────────────────────────────"
if [[ "${FAIL}" -eq 0 ]]; then
  green "Deployment summary: ${PASS} checks passed"
  echo ""
  echo "Post-deployment verification:"
  echo "  Grafana (local):  curl -sf http://127.0.0.1:3000/api/health"
  echo "  Grafana (public): curl -I https://grafana-staging.ixora-app.app"
  echo "  OTLP (public):    curl -o /dev/null -w '%{http_code}' https://otel-staging.ixora-app.app/v1/traces"
  echo "  Expect: Grafana -> 200/302, OTLP -> 401/405 (auth required - proves Caddy routing works)"
  exit 0
else
  red "Deployment completed with ${FAIL} failure(s), ${PASS} passed"
  exit 1
fi
