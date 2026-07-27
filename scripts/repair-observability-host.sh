#!/usr/bin/env bash
# ============================================================
# Ixora Observability - Idempotent host repair script
#
# Repairs an existing observability Droplet without recreating it.
# Safe to re-run multiple times (idempotent).
#
# Responsibilities:
#   - Check SSH connectivity
#   - Install Docker (if absent)
#   - Install Docker Compose plugin (if absent)
#   - Install Caddy (if absent)
#   - Create/update /etc/caddy/Caddyfile
#   - Validate and reload Caddy
#   - Create /opt/ixora-observability
#   - Install/update systemd service and preflight script
#   - Run daemon-reload and enable services
#
# This script does NOT:
#   - Deploy the collector stack (use deploy-observability.sh for that)
#   - Create or overwrite collector/.env (use bootstrap-collector-env.sh)
#   - Delete volumes or observability data
#
# Usage:
#   ./scripts/repair-observability-host.sh \
#     --host 143.198.36.226 \
#     --user root
#
# Optional:
#   --deploy-path /opt/ixora-observability   (default)
#   --grafana-hostname grafana-staging.ixora-app.app   (default)
#   --otel-hostname otel-staging.ixora-app.app   (default)
#   --ssh-key /path/to/key   (uses SSH agent or ~/.ssh/id_* by default)
#   --dry-run   (show what would be done without executing)
# ============================================================

set -euo pipefail

# shellcheck disable=SC2034  # Used implicitly when scripts are sourced; preserved for consistency.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Defaults ──────────────────────────────────────────────────────────────

HOST=""
SSH_USER="root"
DEPLOY_PATH="/opt/ixora-observability"
GRAFANA_HOSTNAME="grafana-staging.ixora-app.app"
OTEL_HOSTNAME="otel-staging.ixora-app.app"
SSH_KEY_PATH=""
DRY_RUN=0

PASS=0
FAIL=0

# ── Argument parsing ──────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)            HOST="$2";             shift 2 ;;
    --user)            SSH_USER="$2";         shift 2 ;;
    --deploy-path)     DEPLOY_PATH="$2";      shift 2 ;;
    --grafana-hostname) GRAFANA_HOSTNAME="$2"; shift 2 ;;
    --otel-hostname)   OTEL_HOSTNAME="$2";    shift 2 ;;
    --ssh-key)         SSH_KEY_PATH="$2";   shift 2 ;;
    --dry-run)         DRY_RUN=1;             shift ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "${HOST}" ]]; then
  printf 'ERROR: --host is required\n' >&2
  printf 'Usage: %s --host <ip> --user <user>\n' "$0" >&2
  exit 1
fi

# ── Output helpers ────────────────────────────────────────────────────────

green()  { printf '\033[0;32m[OK]   %s\033[0m\n' "$*"; ((PASS++)) || true; }
red()    { printf '\033[0;31m[FAIL] %s\033[0m\n' "$*" >&2; ((FAIL++)) || true; }
yellow() { printf '\033[0;33m[SKIP] %s\033[0m\n' "$*"; }
info()   { printf '\033[0;34m[....] %s\033[0m\n' "$*"; }
step()   { echo ""; echo "== $*"; }

# StrictHostKeyChecking=accept-new: accept new host keys, but refuse
# connections when the key changes for a known host. A mismatch must
# be investigated, not silently ignored.
SSH_OPTIONS=(
  -o BatchMode=yes
  -o ConnectTimeout=10
  -o StrictHostKeyChecking=accept-new
)

SSH_KEY_ARGS=()
[[ -n "${SSH_KEY_PATH}" ]] && SSH_KEY_ARGS=(-i "${SSH_KEY_PATH}")

ssh_run() {
  ssh "${SSH_OPTIONS[@]}" "${SSH_KEY_ARGS[@]}" "${SSH_USER}@${HOST}" -- "$@"
}

# Runs a remote command. In dry-run mode just prints it.
remote() {
  local label="$1"
  shift
  local cmd="$*"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    yellow "[DRY-RUN] ${label}: ${cmd}"
    return 0
  fi
  if ssh_run "${cmd}"; then
    green "${label}"
    return 0
  else
    red "${label}"
    return 1
  fi
}

# Same but captures output.
remote_output() {
  ssh_run "$@" 2>/dev/null || true
}

# Uploads file content to a remote path atomically.
remote_write() {
  local dest="$1"
  local mode="$2"
  local content="$3"
  local label="$4"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    yellow "[DRY-RUN] Write ${dest} (mode ${mode})"
    return 0
  fi

  local tmp_remote
  tmp_remote="$(remote_output 'mktemp /tmp/ixora-repair-XXXXXX')"
  if [[ -z "${tmp_remote}" ]]; then
    red "Could not create remote temp file for ${dest}"
    return 1
  fi

  printf '%s' "${content}" | ssh_run "cat > ${tmp_remote} && chmod ${mode} ${tmp_remote} && mv ${tmp_remote} ${dest} && chmod ${mode} ${dest}"
  green "${label}"
}

# ── Step 0: Connectivity check ────────────────────────────────────────────

step "Connectivity"

if [[ "${DRY_RUN}" -eq 0 ]]; then
  if ! ssh_run 'echo ok' >/dev/null 2>&1; then
    red "SSH connection failed to ${SSH_USER}@${HOST}"
    printf 'Hint: Check --ssh-key, authorized_keys, and firewall rules\n' >&2
    printf 'If you see a host key mismatch, investigate before proceeding:\n' >&2
    printf '  ssh-keygen -R %s   # only after confirming the Droplet IP is legitimate\n' \
      "${HOST}" >&2
    exit 1
  fi
  green "SSH connection to ${SSH_USER}@${HOST}"

  # shellcheck disable=SC2016  # Variables must expand on remote shell, not locally
  OS_ID="$(remote_output '. /etc/os-release && echo $ID')"
  # shellcheck disable=SC2016
  OS_VERSION="$(remote_output '. /etc/os-release && echo $VERSION_ID')"
  info "Remote OS: ${OS_ID} ${OS_VERSION}"
else
  yellow "[DRY-RUN] SSH connectivity check skipped"
fi

# ── Step 1: Docker ────────────────────────────────────────────────────────

step "Docker"

DOCKER_INSTALLED=0
if [[ "${DRY_RUN}" -eq 0 ]]; then
  if remote_output 'command -v docker' | grep -q docker; then
    DOCKER_INSTALLED=1
  fi
fi

if [[ "${DOCKER_INSTALLED}" -eq 1 ]]; then
  green "Docker already installed"
  remote "Docker active" 'systemctl is-active docker || systemctl start docker'
else
  info "Installing Docker..."
  remote "Docker: install GPG key" \
    'curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg'
  # shellcheck disable=SC2016  # $(...) must expand on remote shell, not locally
  remote "Docker: add repository" \
    'bash -lc '"'"'echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list'"'"''
  remote "Docker: apt-get update" 'apt-get update -qq'
  remote "Docker: install packages" 'apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin'
  remote "Docker: enable and start" 'systemctl enable --now docker'
fi

# Check Compose plugin
COMPOSE_OK=0
if [[ "${DRY_RUN}" -eq 0 ]]; then
  if remote_output 'docker compose version' 2>/dev/null | grep -q 'Docker Compose'; then
    COMPOSE_OK=1
  fi
fi
if [[ "${COMPOSE_OK}" -eq 1 ]]; then
  green "Docker Compose plugin available"
else
  info "Installing Docker Compose plugin..."
  remote "Docker Compose plugin: install" 'apt-get install -y docker-compose-plugin'
fi

# ── Step 2: Caddy ─────────────────────────────────────────────────────────

step "Caddy"

CADDY_INSTALLED=0
if [[ "${DRY_RUN}" -eq 0 ]]; then
  if remote_output 'command -v caddy' | grep -q caddy; then
    CADDY_INSTALLED=1
  fi
fi

if [[ "${CADDY_INSTALLED}" -eq 1 ]]; then
  green "Caddy already installed"
else
  info "Installing Caddy..."
  remote "Caddy: install prerequisites" \
    'apt-get install -y debian-keyring debian-archive-keyring apt-transport-https'
  remote "Caddy: add GPG key" \
    "curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg"
  remote "Caddy: add repository" \
    "curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list"
  remote "Caddy: apt-get update" 'apt-get update -qq'
  remote "Caddy: install" 'apt-get install -y caddy'
fi

# Defensive repair for interrupted Caddy package configuration. The systemd
# unit runs as User=caddy/Group=caddy, so ensure that account and its runtime
# directories exist before validating or starting the service.
remote "Caddy: ensure system group" \
  'getent group caddy >/dev/null || groupadd --system caddy'
remote "Caddy: ensure system user" \
  'getent passwd caddy >/dev/null || useradd --system --gid caddy --home-dir /var/lib/caddy --create-home --shell /usr/sbin/nologin caddy'
remote "Caddy: ensure data directory" \
  'install -d -o caddy -g caddy -m 0755 /var/lib/caddy'
remote "Caddy: ensure log directory" \
  'install -d -o caddy -g caddy -m 0755 /var/log/caddy'
remote "Caddy: finish interrupted package configuration" \
  'env DEBIAN_FRONTEND=noninteractive dpkg --force-confold --configure -a || true'
remote "Caddy: reset failed state" 'systemctl reset-failed caddy || true'

# ── Step 3: Caddyfile ────────────────────────────────────────────────────

step "Caddyfile"

CADDYFILE="# Grafana - HTTPS reverse proxy to localhost-only Grafana (:3000)
${GRAFANA_HOSTNAME} {
    @blocked_paths {
        path /.env
        path /.env.*
        path /.git/*
        path /.git
        path /config.json
        path /wp-admin/*
        path /wp-login.php
    }
    respond @blocked_paths 404

    header {
        X-Content-Type-Options \"nosniff\"
        X-Frame-Options \"SAMEORIGIN\"
        Referrer-Policy \"strict-origin-when-cross-origin\"
        -Server
    }

    reverse_proxy 127.0.0.1:3000
}

# OTLP HTTP - HTTPS reverse proxy to Collector (:4318)
${OTEL_HOSTNAME} {
    @non_otlp {
        not path /v1/traces
        not path /v1/metrics
        not path /v1/logs
    }
    respond @non_otlp 404

    header {
        X-Content-Type-Options \"nosniff\"
        -Server
    }

    reverse_proxy 127.0.0.1:4318
}
"

remote_write "/etc/caddy/Caddyfile" "644" "${CADDYFILE}" "Caddyfile written"

# Validate Caddy config
remote "Caddy config validate" 'caddy validate --config /etc/caddy/Caddyfile'

# Reload (or start) Caddy
remote "Caddy reload/start" \
  'if systemctl is-active caddy >/dev/null 2>&1; then systemctl reload caddy; else systemctl enable --now caddy; fi'

remote "Caddy active" 'systemctl is-active caddy'

# ── Step 4: Deploy path and directories ──────────────────────────────────

step "Deploy path"

remote "Create deploy path" "mkdir -p ${DEPLOY_PATH}/collector && chmod 755 ${DEPLOY_PATH}"
green "Deploy path: ${DEPLOY_PATH}"

# ── Step 5: Systemd unit and preflight ───────────────────────────────────

step "Systemd unit"

PREFLIGHT_SCRIPT="#!/usr/bin/env bash
set -euo pipefail
DEPLOY_PATH=\"${DEPLOY_PATH}\"
ENV_FILE=\"\${DEPLOY_PATH}/collector/.env\"
if [[ ! -f \"\${ENV_FILE}\" ]]; then
  echo \"ERROR: \${ENV_FILE} missing - run bootstrap-collector-env.sh first\" >&2
  exit 1
fi
if [[ \"\$(stat -c '%a' \"\${ENV_FILE}\")\" != \"600\" ]]; then
  echo \"ERROR: \${ENV_FILE} must be chmod 600\" >&2
  exit 1
fi
if grep -q 'REPLACE_WITH_STRONG' \"\${ENV_FILE}\"; then
  echo \"ERROR: placeholder secrets remain in \${ENV_FILE}\" >&2
  exit 1
fi
if grep -q '^GF_SERVER_ROOT_URL=http://localhost' \"\${ENV_FILE}\"; then
  echo \"ERROR: GF_SERVER_ROOT_URL still points to localhost - set staging HTTPS URL\" >&2
  exit 1
fi
echo \"Preflight OK\"
"

SYSTEMD_UNIT="[Unit]
Description=Ixora Observability Stack (Docker Compose)
Documentation=https://github.com/lucasbrito90/ixora-infra/tree/develop/collector
After=docker.service network-online.target caddy.service
Wants=network-online.target
Requires=docker.service
ConditionPathExists=${DEPLOY_PATH}/collector/docker-compose.yml

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${DEPLOY_PATH}/collector
ExecStartPre=/usr/local/sbin/ixora-observability-preflight.sh
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose stop
ExecReload=/usr/bin/docker compose up -d
TimeoutStartSec=600

[Install]
WantedBy=multi-user.target
"

remote_write "/usr/local/sbin/ixora-observability-preflight.sh" "755" "${PREFLIGHT_SCRIPT}" "Preflight script installed"
remote_write "/etc/systemd/system/ixora-observability.service" "644" "${SYSTEMD_UNIT}" "Systemd unit installed"
remote "systemd daemon-reload" 'systemctl daemon-reload'
remote "ixora-observability.service enabled" 'systemctl enable ixora-observability.service'

# ── Step 6: Port check ───────────────────────────────────────────────────

step "Network verification"

if [[ "${DRY_RUN}" -eq 0 ]]; then
  PORT_443="$(remote_output 'ss -lntp 2>/dev/null | grep :443 | head -3')"
  if echo "${PORT_443}" | grep -q ':443'; then
    green "Port 443 (Caddy) is listening"
  else
    yellow "Port 443 not yet listening - Caddy may need a moment after reload"
  fi
fi

# ── Step 7: Security check ───────────────────────────────────────────────

step "Security verification"

if [[ "${DRY_RUN}" -eq 0 ]]; then
  # Verify internal service ports are NOT publicly bound
  EXPOSED_PORTS="$(remote_output 'ss -lntp 2>/dev/null | grep -E ":(3000|4317|4318|4319|9090|3100|3200) " || true')"
  if [[ -z "${EXPOSED_PORTS}" ]]; then
    green "Internal service ports (3000, 4317-4319, 9090, 3100, 3200) not publicly exposed"
  else
    yellow "Some ports visible via ss (may be Docker 127.0.0.1 bindings - verify they are not 0.0.0.0):"
    echo "${EXPOSED_PORTS}"
    EXPOSED_PUBLIC="$(echo "${EXPOSED_PORTS}" | grep -v '127.0.0.1' || true)"
    if [[ -n "${EXPOSED_PUBLIC}" ]]; then
      red "WARNING: Non-localhost bindings detected on internal ports:"
      echo "${EXPOSED_PUBLIC}" >&2
    else
      green "All bindings are on 127.0.0.1 (OK)"
    fi
  fi
fi

# ── Summary ───────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────"
if [[ "${FAIL}" -eq 0 ]]; then
  green "Host repair complete: ${PASS} checks passed"
  echo ""
  echo "Next steps (first-deployment order):"
  echo ""
  echo "  Step 3: Sync repository files (no containers started):"
  echo "     ./scripts/deploy-observability.sh --host ${HOST} --user ${SSH_USER} --sync-only"
  echo ""
  echo "  Step 4: Create collector/.env on the remote host:"
  echo "     ssh ${SSH_USER}@${HOST}"
  echo "     cd ${DEPLOY_PATH}"
  echo "     export OTEL_INGEST_API_KEY_BACKEND=\"\$(openssl rand -hex 32)\""
  echo "     export OTEL_INGEST_API_KEY_MOBILE=\"\$(openssl rand -hex 32)\""
  echo "     export GF_ADMIN_PASSWORD=\"\$(openssl rand -base64 24)\""
  echo "     export GF_SERVER_ROOT_URL=\"https://${GRAFANA_HOSTNAME}\""
  echo "     ./scripts/bootstrap-collector-env.sh"
  echo "     exit"
  echo ""
  echo "  Step 5: Run the full deployment:"
  echo "     ./scripts/deploy-observability.sh --host ${HOST} --user ${SSH_USER}"
  exit 0
else
  red "Host repair completed with ${FAIL} failure(s)"
  exit 1
fi
