#!/usr/bin/env bash
# ============================================================
# Ixora Observability - Docker Compose deployment
# Phase 8.8.5 - Observability Infrastructure Provisioning
# Phase 8.8.6 - release ref support (IXORA_GIT_REF)
#
# MODES
#   Remote, full deploy (from operator machine):
#     ./scripts/deploy-observability.sh --host <ip> --user root
#     Rsyncs repository source to the Droplet, then SSHes in to run
#     the local deployment steps. Never copies .git, state, or secrets.
#
#   Remote, sync only (files without starting containers):
#     ./scripts/deploy-observability.sh --host <ip> --user root --sync-only
#     Use this for the first deployment, before .env exists on the host.
#
#   Local (run directly on the observability host):
#     cd /opt/ixora-observability
#     ./scripts/deploy-observability.sh
#
# FIRST DEPLOYMENT ORDER (no .env yet)
#   Step 1:  ./scripts/validate-cloud-init.sh
#   Step 2:  ./scripts/repair-observability-host.sh --host <ip> --user root
#   Step 3:  ./scripts/deploy-observability.sh --host <ip> --user root --sync-only
#   Step 4:  ssh root@<ip>
#            cd /opt/ixora-observability
#            export OTEL_INGEST_API_KEY_BACKEND="$(openssl rand -hex 32)"
#            export OTEL_INGEST_API_KEY_MOBILE="$(openssl rand -hex 32)"
#            export GF_ADMIN_PASSWORD="$(openssl rand -base64 24)"
#            export GF_SERVER_ROOT_URL="https://grafana-staging.ixora-app.app"
#            ./scripts/bootstrap-collector-env.sh
#            exit
#   Step 5:  ./scripts/deploy-observability.sh --host <ip> --user root
#
# OPTIONS
#   --host <ip>          Remote host IP or hostname
#   --user <user>        SSH user (default: root)
#   --ssh-key <path>     Path to SSH private key
#   --sync-only          Sync files only; do not start containers
#   --dry-run            Show what would happen without making changes
#   --help               Show this help
#
# ENVIRONMENT VARIABLES
#   IXORA_DEPLOY_PATH      Override deploy path (default: /opt/ixora-observability)
#   IXORA_GIT_REF          Optional Git tag/branch to checkout before deploy
#   SKIP_GRAFANA_VALIDATE  Set to 1 to skip validate.sh
#   GF_ADMIN_PASSWORD      Required for Grafana validation (never logged)
#   SKIP_IMAGE_PULL        Set to 1 to skip docker compose pull
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── Shared SSH options ────────────────────────────────────────────────────
#
# StrictHostKeyChecking=accept-new: accept new host keys automatically,
# but refuse to connect if the key changes for a known host. A key
# mismatch must be investigated, not silently bypassed.
#
SSH_OPTIONS=(
  -o BatchMode=yes
  -o ConnectTimeout=10
  -o StrictHostKeyChecking=accept-new
)

# ── Argument parsing ──────────────────────────────────────────────────────

REMOTE_HOST=""
REMOTE_USER="root"
SSH_KEY_PATH=""
DRY_RUN=0
SYNC_ONLY=0

usage() {
  grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \{0,1\}//' | sed '1,/^$/{/^OPTIONS/,$!d}'
  cat <<'EOF'
Usage:
  ./scripts/deploy-observability.sh [--host <ip>] [--user <user>] [--sync-only] [--dry-run]

Options:
  --host <ip>      Remote host IP or hostname (required for remote mode)
  --user <user>    SSH user (default: root)
  --ssh-key <path> Path to SSH private key
  --sync-only      Sync files only; do not start containers
  --dry-run        Show what would happen without making changes
  --help           Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)      REMOTE_HOST="$2";    shift 2 ;;
    --user)      REMOTE_USER="$2";    shift 2 ;;
    --ssh-key)   SSH_KEY_PATH="$2";   shift 2 ;;
    --sync-only) SYNC_ONLY=1;         shift ;;
    --dry-run)   DRY_RUN=1;           shift ;;
    --help|-h)   usage; exit 0 ;;
    *)
      printf 'ERROR: Unknown argument: %s\n' "$1" >&2
      printf 'Run with --help for usage.\n' >&2
      exit 1
      ;;
  esac
done

# --sync-only requires --host
if [[ "${SYNC_ONLY}" -eq 1 && -z "${REMOTE_HOST}" ]]; then
  printf 'ERROR: --sync-only requires --host\n' >&2
  exit 1
fi

# ── Remote mode ───────────────────────────────────────────────────────────

if [[ -n "${REMOTE_HOST}" ]]; then
  # Build SSH key args array
  SSH_KEY_ARGS=()
  if [[ -n "${SSH_KEY_PATH}" ]]; then
    SSH_KEY_ARGS=(-i "${SSH_KEY_PATH}")
  fi

  DEPLOY_PATH="${IXORA_DEPLOY_PATH:-/opt/ixora-observability}"
  MODE_LABEL="full deploy"
  [[ "${SYNC_ONLY}" -eq 1 ]] && MODE_LABEL="sync-only"
  [[ "${DRY_RUN}" -eq 1 ]]   && MODE_LABEL="${MODE_LABEL} (dry-run)"

  printf '\033[0;34m[INFO] Remote mode: %s@%s -> %s [%s]\033[0m\n' \
    "${REMOTE_USER}" "${REMOTE_HOST}" "${DEPLOY_PATH}" "${MODE_LABEL}"

  # Helper: run SSH command
  ssh_run() {
    ssh "${SSH_OPTIONS[@]}" "${SSH_KEY_ARGS[@]}" "${REMOTE_USER}@${REMOTE_HOST}" -- "$@"
  }

  # Helper: build rsync SSH transport string (safe for -e)
  rsync_ssh_transport() {
    local parts="ssh"
    for opt in "${SSH_OPTIONS[@]}"; do
      parts="${parts} ${opt}"
    done
    for key_arg in "${SSH_KEY_ARGS[@]}"; do
      parts="${parts} ${key_arg}"
    done
    printf '%s' "${parts}"
  }

  # ── Verify SSH connectivity ──────────────────────────────────────────
  printf '\033[0;34m[INFO] Checking SSH connectivity...\033[0m\n'
  if ! ssh_run 'echo ok' >/dev/null 2>&1; then
    printf '\033[0;31m[FAIL] SSH connection failed to %s@%s\033[0m\n' \
      "${REMOTE_USER}" "${REMOTE_HOST}" >&2
    printf 'Hint: verify --ssh-key, authorized_keys, and firewall allow your source IP on port 22\n' >&2
    printf 'If you receive a host key mismatch error, investigate before proceeding:\n' >&2
    printf '  ssh-keygen -R %s   # only after confirming the Droplet IP is legitimate\n' \
      "${REMOTE_HOST}" >&2
    exit 1
  fi
  printf '\033[0;32m[OK]   SSH connection to %s@%s\033[0m\n' "${REMOTE_USER}" "${REMOTE_HOST}"

  # ── Verify Docker (required for full deploy, warn for sync-only) ─────
  if ! ssh_run 'command -v docker >/dev/null' 2>/dev/null; then
    if [[ "${SYNC_ONLY}" -eq 1 ]]; then
      printf '\033[0;33m[WARN] Docker not found on remote - run repair-observability-host.sh before full deploy\033[0m\n'
    else
      printf '\033[0;31m[FAIL] Docker not installed on remote.\033[0m\n' >&2
      printf '  Run first: ./scripts/repair-observability-host.sh --host %s --user %s\033[0m\n' \
        "${REMOTE_HOST}" "${REMOTE_USER}" >&2
      exit 1
    fi
  else
    printf '\033[0;32m[OK]   Docker present on remote\033[0m\n'
  fi

  # Caddy check (warn only - not fatal for sync-only)
  if ! ssh_run 'systemctl is-active caddy >/dev/null 2>&1' 2>/dev/null; then
    printf '\033[0;33m[WARN] Caddy is not active on remote - run repair-observability-host.sh first\033[0m\n'
  else
    printf '\033[0;32m[OK]   Caddy active on remote\033[0m\n'
  fi

  # ── Verify local source directories ──────────────────────────────────
  if [[ ! -d "${REPO_ROOT}/collector" ]]; then
    printf '\033[0;31m[FAIL] Local collector/ not found at %s\033[0m\n' "${REPO_ROOT}/collector" >&2
    exit 1
  fi
  if [[ ! -f "${REPO_ROOT}/collector/docker-compose.yml" ]]; then
    printf '\033[0;31m[FAIL] collector/docker-compose.yml not found\033[0m\n' >&2
    exit 1
  fi
  printf '\033[0;32m[OK]   Local collector/ verified\033[0m\n'

  # ── Create deploy path on remote ─────────────────────────────────────
  if [[ "${DRY_RUN}" -eq 0 ]]; then
    ssh_run "mkdir -p ${DEPLOY_PATH}/collector && chmod 755 ${DEPLOY_PATH}"
  else
    printf '\033[0;33m[DRY-RUN] Would create %s/collector on remote\033[0m\n' "${DEPLOY_PATH}"
  fi

  # ── Build rsync exclude list ──────────────────────────────────────────
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

  RSYNC_TRANSPORT="$(rsync_ssh_transport)"

  # ── rsync collector/ ─────────────────────────────────────────────────
  printf '\033[0;34m[INFO] Syncing collector/ to %s:%s/collector/...\033[0m\n' \
    "${REMOTE_HOST}" "${DEPLOY_PATH}"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    rsync -avzn \
      "${RSYNC_EXCLUDE[@]}" \
      --protect-args \
      -e "${RSYNC_TRANSPORT}" \
      "${REPO_ROOT}/collector/" \
      "${REMOTE_USER}@${REMOTE_HOST}:${DEPLOY_PATH}/collector/"
    printf '\033[0;33m[DRY-RUN] rsync shown above - no files transferred\033[0m\n'
  else
    rsync -avz \
      "${RSYNC_EXCLUDE[@]}" \
      --protect-args \
      --no-perms \
      -e "${RSYNC_TRANSPORT}" \
      "${REPO_ROOT}/collector/" \
      "${REMOTE_USER}@${REMOTE_HOST}:${DEPLOY_PATH}/collector/"
    printf '\033[0;32m[OK]   collector/ synced to remote\033[0m\n'
  fi

  # ── rsync scripts/ ───────────────────────────────────────────────────
  printf '\033[0;34m[INFO] Syncing scripts/ to remote...\033[0m\n'
  if [[ "${DRY_RUN}" -eq 0 ]]; then
    rsync -avz \
      --exclude='.git' \
      --protect-args \
      --no-perms \
      -e "${RSYNC_TRANSPORT}" \
      "${REPO_ROOT}/scripts/" \
      "${REMOTE_USER}@${REMOTE_HOST}:${DEPLOY_PATH}/scripts/"
    ssh_run "chmod +x ${DEPLOY_PATH}/scripts/*.sh 2>/dev/null || true"
    printf '\033[0;32m[OK]   scripts/ synced to remote\033[0m\n'
  else
    printf '\033[0;33m[DRY-RUN] Would sync scripts/ to %s:%s/scripts/\033[0m\n' \
      "${REMOTE_HOST}" "${DEPLOY_PATH}"
  fi

  # ── rsync docs/runbooks/ ─────────────────────────────────────────────
  #
  # validate.sh (checks 96, 102) resolves runbooks relative to the deploy
  # root as ${DEPLOY_PATH}/docs/runbooks/ (SCRIPT_DIR_PARENT/docs from
  # collector/grafana/validate.sh). Alert rule `runbook` annotations also
  # link to /runbooks/<slug>.md, which the reverse proxy is expected to
  # serve from this path. Found missing during Phase 9's first real
  # deploy — validate.sh reported all 7 runbooks absent on the host even
  # though they exist in the repo, because nothing ever synced them.
  printf '\033[0;34m[INFO] Syncing docs/runbooks/ to remote...\033[0m\n'
  if [[ "${DRY_RUN}" -eq 0 ]]; then
    ssh_run "mkdir -p ${DEPLOY_PATH}/docs/runbooks"
    rsync -avz \
      --exclude='.git' \
      --protect-args \
      --no-perms \
      -e "${RSYNC_TRANSPORT}" \
      "${REPO_ROOT}/docs/runbooks/" \
      "${REMOTE_USER}@${REMOTE_HOST}:${DEPLOY_PATH}/docs/runbooks/"
    printf '\033[0;32m[OK]   docs/runbooks/ synced to remote\033[0m\n'
  else
    printf '\033[0;33m[DRY-RUN] Would sync docs/runbooks/ to %s:%s/docs/runbooks/\033[0m\n' \
      "${REMOTE_HOST}" "${DEPLOY_PATH}"
  fi

  # ── Fix permissions; never touch .env ────────────────────────────────
  if [[ "${DRY_RUN}" -eq 0 ]]; then
    ssh_run "chown -R root:root ${DEPLOY_PATH}/collector && chmod -R o-w ${DEPLOY_PATH}/collector"
    # Preserve .env ownership and permissions if it already exists
    ssh_run "test -f ${DEPLOY_PATH}/collector/.env && chmod 600 ${DEPLOY_PATH}/collector/.env || true"
    printf '\033[0;32m[OK]   Permissions set on remote\033[0m\n'
  fi

  # ── Sync-only: stop here ─────────────────────────────────────────────
  if [[ "${SYNC_ONLY}" -eq 1 ]]; then
    echo ""
    echo "────────────────────────────────────────────────"
    printf '\033[0;32m[OK]   Sync-only complete. Files synchronized to %s:%s\033[0m\n' \
      "${REMOTE_HOST}" "${DEPLOY_PATH}"
    echo ""
    echo "Next step: bootstrap collector/.env on the remote host."
    echo ""
    echo "  ssh ${REMOTE_USER}@${REMOTE_HOST}"
    echo "  cd ${DEPLOY_PATH}"
    echo "  export OTEL_INGEST_API_KEY_BACKEND=\"\$(openssl rand -hex 32)\""
    echo "  export OTEL_INGEST_API_KEY_MOBILE=\"\$(openssl rand -hex 32)\""
    echo "  export GF_ADMIN_PASSWORD=\"\$(openssl rand -base64 24)\""
    echo "  export GF_SERVER_ROOT_URL=\"https://grafana-staging.ixora-app.app\""
    echo "  ./scripts/bootstrap-collector-env.sh"
    echo "  exit"
    echo ""
    echo "Then run the full deployment:"
    echo "  ./scripts/deploy-observability.sh --host ${REMOTE_HOST} --user ${REMOTE_USER}"
    exit 0
  fi

  # ── Full deploy: run local deploy on remote via SSH ──────────────────
  printf '\033[0;34m[INFO] Running full deployment on remote...\033[0m\n'
  if [[ "${DRY_RUN}" -eq 0 ]]; then
    REMOTE_ENV_VARS="IXORA_DEPLOY_PATH=${DEPLOY_PATH}"
    [[ -n "${IXORA_GIT_REF:-}" ]]        && REMOTE_ENV_VARS="${REMOTE_ENV_VARS} IXORA_GIT_REF=${IXORA_GIT_REF}"
    [[ "${SKIP_GRAFANA_VALIDATE:-0}" == "1" ]] && REMOTE_ENV_VARS="${REMOTE_ENV_VARS} SKIP_GRAFANA_VALIDATE=1"
    [[ "${SKIP_IMAGE_PULL:-0}" == "1" ]] && REMOTE_ENV_VARS="${REMOTE_ENV_VARS} SKIP_IMAGE_PULL=1"

    ssh_run "cd ${DEPLOY_PATH} && env ${REMOTE_ENV_VARS} ./scripts/deploy-observability.sh"
  else
    printf '\033[0;33m[DRY-RUN] Would run: ssh %s@%s "cd %s && ./scripts/deploy-observability.sh"\033[0m\n' \
      "${REMOTE_USER}" "${REMOTE_HOST}" "${DEPLOY_PATH}"
  fi

  exit $?
fi

# ── Local mode: run directly on the observability host ───────────────────

DEPLOY_PATH="${IXORA_DEPLOY_PATH:-/opt/ixora-observability}"
COLLECTOR_DIR="${DEPLOY_PATH}/collector"
ENV_FILE="${COLLECTOR_DIR}/.env"
MARKER="/etc/ixora-observability-host"

PASS=0
FAIL=0

green()  { printf '\033[0;32m[OK]   %s\033[0m\n' "$*"; (( PASS++ )) || true; }
red()    { printf '\033[0;31m[FAIL] %s\033[0m\n' "$*"; (( FAIL++ )) || true; }
yellow() { printf '\033[0;33m[WARN] %s\033[0m\n' "$*"; }

step() { echo ""; echo "== $*"; }

fail_hard() {
  red "$1"
  exit 1
}

# ── Preflight ─────────────────────────────────────────────────────────────

step "Preflight"

if [[ -f "${MARKER}" ]]; then
  green "Observability host marker present"
else
  yellow "Marker ${MARKER} not found - continuing (manual or rebuilt host)"
fi

command -v docker >/dev/null 2>&1 || fail_hard "docker not installed"
docker compose version >/dev/null 2>&1 || fail_hard "docker compose v2 not available"
green "Docker and Compose available"

[[ -d "${COLLECTOR_DIR}" ]]           || fail_hard "Missing ${COLLECTOR_DIR}"
[[ -f "${COLLECTOR_DIR}/docker-compose.yml" ]] || fail_hard "Missing docker-compose.yml"
green "Collector directory present"

[[ -f "${ENV_FILE}" ]]                || fail_hard "Missing ${ENV_FILE} - run scripts/bootstrap-collector-env.sh first"
[[ "$(stat -c '%a' "${ENV_FILE}")" == "600" ]] || fail_hard "${ENV_FILE} must be chmod 600"
green "collector/.env exists with mode 600"

grep -q 'REPLACE_WITH_STRONG' "${ENV_FILE}" && fail_hard "Placeholder secrets remain in ${ENV_FILE}"
grep -q '^GF_SERVER_ROOT_URL=http://localhost' "${ENV_FILE}" && fail_hard "GF_SERVER_ROOT_URL still points to localhost"
grep -q '^GF_SECURITY_COOKIE_SECURE=false' "${ENV_FILE}" && fail_hard "GF_SECURITY_COOKIE_SECURE must be true on staging"
green "No placeholder secrets detected"

# ── Release ref (optional) ────────────────────────────────────────────────

step "Release ref (optional)"

if [[ -n "${IXORA_GIT_REF:-}" ]]; then
  if [[ -d "${DEPLOY_PATH}/.git" ]]; then
    cd "${DEPLOY_PATH}"
    git fetch --tags origin 2>/dev/null || yellow "git fetch failed - continuing with local refs"
    git checkout "${IXORA_GIT_REF}" || fail_hard "git checkout ${IXORA_GIT_REF} failed"
    green "Checked out ${IXORA_GIT_REF}"
  else
    fail_hard "IXORA_GIT_REF set but ${DEPLOY_PATH} is not a git repository"
  fi
fi

# ── Docker Compose validation ─────────────────────────────────────────────

step "Docker Compose validation"

cd "${COLLECTOR_DIR}"
docker compose config >/dev/null || fail_hard "docker compose config failed"
green "docker compose config OK"

# ── Pull images ───────────────────────────────────────────────────────────

if [[ "${SKIP_IMAGE_PULL:-0}" != "1" ]]; then
  step "Pull images"
  docker compose pull
  green "Images pulled"
else
  yellow "Image pull skipped (SKIP_IMAGE_PULL=1)"
fi

# ── Start services ────────────────────────────────────────────────────────

step "Start services"

docker compose up -d
green "docker compose up -d completed"

# ── Mandatory health checks ───────────────────────────────────────────────
#
# All checks are mandatory. A failure exits non-zero.
# On failure: print docker compose ps and the last 100 lines of the
# failing service's logs. Do not expose .env values.
#
step "Mandatory health checks"

HEALTH_FAILED=0

# Maps service label -> health URL and container name
declare -A HEALTH_URLS=(
  ["Collector"]="http://127.0.0.1:13133/health"
  ["Prometheus"]="http://127.0.0.1:9090/-/ready"
  ["Loki"]="http://127.0.0.1:3100/ready"
  ["Tempo"]="http://127.0.0.1:3200/ready"
  ["Grafana"]="http://127.0.0.1:3000/api/health"
)
declare -A HEALTH_CONTAINERS=(
  ["Collector"]="collector"
  ["Prometheus"]="prometheus"
  ["Loki"]="loki"
  ["Tempo"]="tempo"
  ["Grafana"]="grafana"
)
declare -A HEALTH_ATTEMPTS=(
  ["Collector"]=30
  ["Prometheus"]=30
  ["Loki"]=30
  ["Tempo"]=30
  ["Grafana"]=45
)

wait_http_mandatory() {
  local label="$1"
  local url="$2"
  local max_attempts="$3"
  local retry_interval=2
  local i
  for (( i=1; i<=max_attempts; i++ )); do
    if curl -sf "${url}" >/dev/null 2>&1; then
      green "${label} healthy (${url})"
      return 0
    fi
    printf '\033[0;34m[INFO] %s not ready yet, attempt %d/%d (retry in %ds)...\033[0m\n' \
      "${label}" "${i}" "${max_attempts}" "${retry_interval}"
    sleep "${retry_interval}"
  done
  return 1
}

for SERVICE in Collector Prometheus Loki Tempo Grafana; do
  URL="${HEALTH_URLS[${SERVICE}]}"
  CONTAINER="${HEALTH_CONTAINERS[${SERVICE}]}"
  ATTEMPTS="${HEALTH_ATTEMPTS[${SERVICE}]}"

  if ! wait_http_mandatory "${SERVICE}" "${URL}" "${ATTEMPTS}"; then
    red "${SERVICE} UNHEALTHY after $((ATTEMPTS * 2))s (${URL})"
    HEALTH_FAILED=1
    echo ""
    printf '\033[0;31m[DIAG] Container status:\033[0m\n'
    docker compose ps 2>/dev/null || true
    echo ""
    printf '\033[0;31m[DIAG] Last 100 lines from %s container:\033[0m\n' "${CONTAINER}"
    docker compose logs --tail=100 "${CONTAINER}" 2>/dev/null || true
    echo ""
  fi
done

if [[ "${HEALTH_FAILED}" -ne 0 ]]; then
  red "One or more mandatory services are unhealthy. Deployment FAILED."
  echo ""
  echo "Troubleshooting steps:"
  echo "  1. Check container logs:  docker compose logs --tail=200 <service>"
  echo "  2. Check .env values:     cat ${ENV_FILE} | grep -v '=.*\S' (blank lines only)"
  echo "  3. Validate compose file: docker compose config"
  echo "  4. Check port bindings:   ss -lntp | grep -E ':(3000|4317|4318|9090|3100|3200)'"
  exit 1
fi

# ── Service status ────────────────────────────────────────────────────────

step "Service status"

docker compose ps

EXPECTED=(ixora-otel-collector ixora-prometheus ixora-loki ixora-tempo ixora-grafana)
for svc in "${EXPECTED[@]}"; do
  if docker compose ps 2>/dev/null | grep -q "${svc}"; then
    green "Container ${svc} present"
  else
    red "Container ${svc} missing"
  fi
done

# ── Port binding verification ─────────────────────────────────────────────

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
    yellow "Port ${port} not yet listed by ss"
  fi
done

# ── Volume persistence check ──────────────────────────────────────────────

step "Volume persistence check"

for vol in prometheus_data loki_data tempo_data grafana_data; do
  if docker volume inspect "collector_${vol}" >/dev/null 2>&1 \
     || docker volume inspect "${vol}" >/dev/null 2>&1; then
    green "Volume ${vol} exists"
  else
    yellow "Volume ${vol} not found by expected name - inspect: docker volume ls"
  fi
done

# ── Optional: Grafana validation ─────────────────────────────────────────

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

# ── Enable systemd unit ───────────────────────────────────────────────────

step "Enable systemd unit"

if systemctl list-unit-files ixora-observability.service >/dev/null 2>&1; then
  systemctl enable ixora-observability.service >/dev/null 2>&1 || true
  green "ixora-observability.service enabled for reboot"
else
  yellow "ixora-observability.service not found (install via repair-observability-host.sh)"
fi

# ── Caddy status ─────────────────────────────────────────────────────────

step "Caddy status"

if systemctl is-active caddy >/dev/null 2>&1; then
  green "Caddy service active"
  if ss -lntp 2>/dev/null | grep -q ':443 '; then
    green "Caddy listening on port 443"
  else
    yellow "Port 443 not yet listening - Caddy may still be starting"
  fi
else
  red "Caddy is not active"
fi

# ── Summary ───────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────"
if [[ "${FAIL}" -eq 0 ]]; then
  green "Deployment complete: ${PASS} checks passed"
  echo ""
  echo "Post-deployment verification:"
  echo "  curl -fsS http://127.0.0.1:3000/api/health    # Grafana (local)"
  echo "  curl -I https://grafana-staging.ixora-app.app  # Grafana (public)"
  printf "  curl -o /dev/null -w '%%{http_code}\\n' https://otel-staging.ixora-app.app/v1/traces\\n"
  echo "  # Expect: Grafana -> 200/302, OTLP -> 401/405 (auth required)"
  exit 0
else
  red "Deployment completed with ${FAIL} failure(s) and ${PASS} passed"
  exit 1
fi
