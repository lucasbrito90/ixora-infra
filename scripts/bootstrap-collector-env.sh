#!/usr/bin/env bash
# ============================================================
# Ixora Observability — Secure collector/.env bootstrap
# Phase 8.8.5 — Observability Infrastructure Provisioning
#
# Creates collector/.env from .env.example with staging-safe defaults.
# Secrets are read from the environment — never from arguments or logs.
#
# Usage (on observability host, after git clone):
#   export OTEL_INGEST_API_KEY_BACKEND="$(openssl rand -hex 32)"
#   export OTEL_INGEST_API_KEY_MOBILE="$(openssl rand -hex 32)"
#   export GF_ADMIN_PASSWORD="$(openssl rand -base64 24)"
#   export GF_SERVER_ROOT_URL="https://grafana-staging.ixora-app.app"
#   ./scripts/bootstrap-collector-env.sh
#
# Optional overrides:
#   IXORA_DEPLOY_PATH, OTEL_DEPLOYMENT_ENVIRONMENT, GF_ADMIN_USER
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEPLOY_PATH="${IXORA_DEPLOY_PATH:-/opt/ixora-observability}"
COLLECTOR_DIR="${DEPLOY_PATH}/collector"
ENV_EXAMPLE="${COLLECTOR_DIR}/.env.example"
ENV_FILE="${COLLECTOR_DIR}/.env"

red()   { printf '\033[0;31mERROR: %s\033[0m\n' "$*" >&2; }
green() { printf '\033[0;32m✓ %s\033[0m\n' "$*"; }

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    red "Environment variable ${name} is required but not set"
    exit 1
  fi
  if [[ "${!name}" == *"REPLACE_WITH"* ]]; then
    red "Environment variable ${name} contains placeholder text"
    exit 1
  fi
}

if [[ ! -f "${ENV_EXAMPLE}" ]]; then
  red "Missing ${ENV_EXAMPLE} — clone ixora-infra to ${DEPLOY_PATH} first"
  exit 1
fi

require_env OTEL_INGEST_API_KEY_BACKEND
require_env OTEL_INGEST_API_KEY_MOBILE
require_env GF_ADMIN_PASSWORD
require_env GF_SERVER_ROOT_URL

if [[ "${GF_SERVER_ROOT_URL}" == http://localhost* ]]; then
  red "GF_SERVER_ROOT_URL must be the public HTTPS Grafana URL on staging"
  exit 1
fi

OTEL_DEPLOYMENT_ENVIRONMENT="${OTEL_DEPLOYMENT_ENVIRONMENT:-staging}"
GF_ADMIN_USER="${GF_ADMIN_USER:-admin}"

cp "${ENV_EXAMPLE}" "${ENV_FILE}"
chmod 600 "${ENV_FILE}"

set_kv() {
  local key="$1"
  local value="$2"
  if grep -q "^${key}=" "${ENV_FILE}"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "${ENV_FILE}"
  else
    echo "${key}=${value}" >> "${ENV_FILE}"
  fi
}

set_kv OTEL_DEPLOYMENT_ENVIRONMENT "${OTEL_DEPLOYMENT_ENVIRONMENT}"
set_kv OTEL_INGEST_API_KEY_BACKEND "${OTEL_INGEST_API_KEY_BACKEND}"
set_kv OTEL_INGEST_API_KEY_MOBILE "${OTEL_INGEST_API_KEY_MOBILE}"
set_kv GF_ADMIN_USER "${GF_ADMIN_USER}"
set_kv GF_ADMIN_PASSWORD "${GF_ADMIN_PASSWORD}"
set_kv GF_SERVER_ROOT_URL "${GF_SERVER_ROOT_URL}"
set_kv GF_SECURITY_COOKIE_SECURE "true"
set_kv GF_SECURITY_COOKIE_SAMESITE "strict"
set_kv TEMPO_OTLP_GRPC_PORT "14317"

if grep -q 'REPLACE_WITH_STRONG' "${ENV_FILE}"; then
  red "Placeholder values remain in ${ENV_FILE}"
  exit 1
fi

green "Created ${ENV_FILE} (mode 600)"
green "Next: run ${REPO_ROOT}/scripts/deploy-observability.sh"
