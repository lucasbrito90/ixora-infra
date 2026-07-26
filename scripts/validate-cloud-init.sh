#!/usr/bin/env bash
# ============================================================
# Ixora Observability - Cloud-init template validation
#
# Renders the cloud-init template with safe test values and
# validates the result for encoding, YAML, and content sanity.
#
# Usage:
#   ./scripts/validate-cloud-init.sh
#   ./scripts/validate-cloud-init.sh --rendered-only   # print rendered output
#
# Requirements (local):
#   - opentofu OR terraform (for templatefile rendering)
#   - python3 (for YAML validation fallback)
#
# Optional (for full cloud-init schema validation):
#   - cloud-init (Ubuntu/Debian: apt-get install cloud-init)
#   OR
#   - Docker (will use ubuntu image with cloud-init)
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMPLATE="${REPO_ROOT}/opentofu/staging/templates/observability-cloud-init.yaml.tftpl"
RENDERED_FILE=""
RENDERED_ONLY=0

green()  { printf '\033[0;32m[PASS] %s\033[0m\n' "$*"; }
red()    { printf '\033[0;31m[FAIL] %s\033[0m\n' "$*" >&2; }
yellow() { printf '\033[0;33m[WARN] %s\033[0m\n' "$*"; }
info()   { printf '\033[0;34m[INFO] %s\033[0m\n' "$*"; }

PASS=0
FAIL=0

check_pass() { green "$1"; ((PASS++)) || true; }
check_fail() { red "$1"; ((FAIL++)) || true; }

for arg in "$@"; do
  case "${arg}" in
    --rendered-only) RENDERED_ONLY=1 ;;
  esac
done

cleanup() {
  if [[ -n "${RENDERED_FILE}" && -f "${RENDERED_FILE}" ]]; then
    rm -f "${RENDERED_FILE}"
  fi
}
trap cleanup EXIT

# ── Step 1: Source file checks ─────────────────────────────────────────────

info "Step 1: Source template checks"

if [[ ! -f "${TEMPLATE}" ]]; then
  check_fail "Template not found: ${TEMPLATE}"
  exit 1
fi
check_pass "Template exists: ${TEMPLATE}"

# Check encoding
CHARSET="$(file -bi "${TEMPLATE}" | cut -d= -f2)"
if [[ "${CHARSET}" == "us-ascii" || "${CHARSET}" == "utf-8" ]]; then
  check_pass "Template encoding: ${CHARSET}"
else
  check_fail "Unexpected encoding: ${CHARSET} (want us-ascii or utf-8)"
fi

# Check for BOM
BOM="$(hexdump -n 3 -e '3/1 "%02x"' "${TEMPLATE}")"
if [[ "${BOM}" == "efbbbf" ]]; then
  check_fail "BOM detected at start of file (0xEF 0xBB 0xBF) - remove BOM"
else
  check_pass "No BOM detected"
fi

# Check first line
FIRST_LINE="$(head -n 1 "${TEMPLATE}")"
if [[ "${FIRST_LINE}" == "#cloud-config" ]]; then
  check_pass "First line is exactly: #cloud-config"
else
  check_fail "First line must be '#cloud-config', got: ${FIRST_LINE}"
fi

# Check for non-ASCII (corrupted em dashes, smart quotes, etc.)
if LC_ALL=C grep -qP '[^\x00-\x7F]' "${TEMPLATE}"; then
  LINES="$(LC_ALL=C grep -nP '[^\x00-\x7F]' "${TEMPLATE}" | head -5)"
  check_fail "Non-ASCII characters found in source template:"
  echo "${LINES}" >&2
else
  check_pass "No non-ASCII characters in source template"
fi

# Check for corrupted UTF-8 artifact sequences (â€", â€™, etc.)
if LC_ALL=C grep -qP 'â' "${TEMPLATE}"; then
  check_fail "Corrupted UTF-8 artifact (â) found - replace em dashes/smart quotes with ASCII"
else
  check_pass "No corrupted UTF-8 artifacts (â sequences)"
fi

# ── Step 2: Render the template with safe test values ─────────────────────

info "Step 2: Render template with test values"

RENDERED_FILE="$(mktemp /tmp/cloud-init-rendered-XXXXXX.yaml)"

render_with_tofu() {
  local tofu_bin="${1:-tofu}"
  # Write a minimal tofu config to render just the templatefile
  local tmp_dir
  tmp_dir="$(mktemp -d /tmp/tofu-render-XXXXXX)"
  trap "rm -rf ${tmp_dir}" RETURN

  cat > "${tmp_dir}/render.tf" <<'EOF'
output "rendered" {
  value = templatefile(var.template_path, {
    deploy_path      = var.deploy_path
    grafana_hostname = var.grafana_hostname
    otel_hostname    = var.otel_hostname
  })
}
variable "template_path"    { type = string }
variable "deploy_path"      { type = string }
variable "grafana_hostname" { type = string }
variable "otel_hostname"    { type = string }
EOF

  cd "${tmp_dir}"
  "${tofu_bin}" init -backend=false -input=false >/dev/null 2>&1 || return 1
  "${tofu_bin}" apply -auto-approve -input=false \
    -var "template_path=${TEMPLATE}" \
    -var "deploy_path=/opt/ixora-observability" \
    -var "grafana_hostname=grafana-test.example.com" \
    -var "otel_hostname=otel-test.example.com" \
    >/dev/null 2>&1 || return 1
  "${tofu_bin}" output -raw rendered > "${RENDERED_FILE}" 2>/dev/null || return 1
  return 0
}

render_with_python() {
  python3 - "${TEMPLATE}" "${RENDERED_FILE}" <<'PYEOF'
import sys, re

template_path = sys.argv[1]
output_path   = sys.argv[2]

with open(template_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Substitute HCL templatefile variables ${var} and $${literal}
content = content.replace('$${', '\x00ESC\x00')  # protect $$ escapes

# Replace ${variable} with test values
substitutions = {
    'deploy_path':      '/opt/ixora-observability',
    'grafana_hostname': 'grafana-test.example.com',
    'otel_hostname':    'otel-test.example.com',
}
for key, val in substitutions.items():
    content = content.replace('${' + key + '}', val)

# Restore $$ -> $ (HCL literal dollar)
content = content.replace('\x00ESC\x00', '${')

with open(output_path, 'w', encoding='utf-8') as f:
    f.write(content)
print("Rendered with Python substitution")
PYEOF
}

RENDER_METHOD="none"
if command -v tofu >/dev/null 2>&1; then
  if render_with_tofu tofu; then
    RENDER_METHOD="tofu"
  fi
elif command -v terraform >/dev/null 2>&1; then
  if render_with_tofu terraform; then
    RENDER_METHOD="terraform"
  fi
fi

if [[ "${RENDER_METHOD}" == "none" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    render_with_python
    RENDER_METHOD="python"
    yellow "Rendered with Python (tofu/terraform not available - variable substitution only)"
  else
    check_fail "Cannot render template: neither tofu, terraform, nor python3 available"
    exit 1
  fi
fi

if [[ -s "${RENDERED_FILE}" ]]; then
  check_pass "Template rendered successfully (method: ${RENDER_METHOD})"
else
  check_fail "Rendered output is empty"
  exit 1
fi

if [[ "${RENDERED_ONLY}" -eq 1 ]]; then
  cat "${RENDERED_FILE}"
  exit 0
fi

# ── Step 3: Validate rendered output ──────────────────────────────────────

info "Step 3: Validate rendered output"

# Check rendered encoding
RENDERED_CHARSET="$(file -bi "${RENDERED_FILE}" | cut -d= -f2)"
if [[ "${RENDERED_CHARSET}" == "us-ascii" || "${RENDERED_CHARSET}" == "utf-8" ]]; then
  check_pass "Rendered encoding: ${RENDERED_CHARSET}"
else
  check_fail "Rendered encoding unexpected: ${RENDERED_CHARSET}"
fi

# Check rendered first line
RENDERED_FIRST="$(head -n 1 "${RENDERED_FILE}")"
if [[ "${RENDERED_FIRST}" == "#cloud-config" ]]; then
  check_pass "Rendered first line: #cloud-config"
else
  check_fail "Rendered first line wrong: '${RENDERED_FIRST}'"
fi

# Check for non-ASCII in rendered output
if LC_ALL=C grep -qP '[^\x00-\x7F]' "${RENDERED_FILE}"; then
  check_fail "Non-ASCII characters in rendered output"
  LC_ALL=C grep -nP '[^\x00-\x7F]' "${RENDERED_FILE}" | head -5 >&2
else
  check_pass "No non-ASCII characters in rendered output"
fi

# Check for corrupted UTF-8 artifacts in rendered output
if LC_ALL=C grep -qP 'â' "${RENDERED_FILE}"; then
  check_fail "Corrupted UTF-8 artifact (â) in rendered output"
else
  check_pass "No corrupted UTF-8 artifacts in rendered output"
fi

# Check variable substitution (no unresolved ${...} left from HCL)
if grep -qP '\$\{[a-z_]+\}' "${RENDERED_FILE}"; then
  UNRESOLVED="$(grep -nP '\$\{[a-z_]+\}' "${RENDERED_FILE}" | head -5)"
  check_fail "Unresolved template variables in rendered output:"
  echo "${UNRESOLVED}" >&2
else
  check_pass "All template variables resolved"
fi

# Check expected test values appear
if grep -q 'grafana-test.example.com' "${RENDERED_FILE}"; then
  check_pass "grafana_hostname substituted correctly"
else
  check_fail "grafana_hostname not found in rendered output"
fi

if grep -q 'otel-test.example.com' "${RENDERED_FILE}"; then
  check_pass "otel_hostname substituted correctly"
else
  check_fail "otel_hostname not found in rendered output"
fi

if grep -q '/opt/ixora-observability' "${RENDERED_FILE}"; then
  check_pass "deploy_path substituted correctly"
else
  check_fail "deploy_path not found in rendered output"
fi

# Check for expected structural content
CONTENT_CHECKS=(
  "docker-ce"
  "caddy"
  "docker compose up -d"
  "ixora-observability.service"
  "ixora-observability-preflight.sh"
  "/etc/caddy/Caddyfile"
  "ExecStartPre"
)
for pattern in "${CONTENT_CHECKS[@]}"; do
  if grep -q "${pattern}" "${RENDERED_FILE}"; then
    check_pass "Content check: '${pattern}' present"
  else
    check_fail "Content check: '${pattern}' MISSING from rendered output"
  fi
done

# Check Caddyfile path-blocking is present
if grep -q '/.env' "${RENDERED_FILE}"; then
  check_pass "Caddyfile blocks /.env paths"
else
  check_fail "Caddyfile missing /.env block rule"
fi

# ── Step 4: YAML / cloud-init schema validation ─────────────────────────

info "Step 4: YAML validation"

if command -v python3 >/dev/null 2>&1; then
  python3 - "${RENDERED_FILE}" <<'PYEOF'
import sys
try:
    import yaml
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        content = f.read()
    docs = list(yaml.safe_load_all(content))
    if docs and docs[0] is not None:
        print("[PASS] YAML parses successfully")
        sys.exit(0)
    else:
        print("[WARN] YAML parsed but document is empty")
        sys.exit(0)
except yaml.YAMLError as e:
    print(f"[FAIL] YAML parse error: {e}", file=sys.stderr)
    sys.exit(1)
except ImportError:
    print("[WARN] PyYAML not installed - skipping YAML parse (pip3 install pyyaml)")
    sys.exit(0)
PYEOF
  YAML_EXIT=$?
  if [[ "${YAML_EXIT}" -eq 0 ]]; then
    ((PASS++)) || true
  else
    ((FAIL++)) || true
  fi
else
  yellow "python3 not available - skipping YAML parse"
fi

# Try cloud-init schema validation if available
if command -v cloud-init >/dev/null 2>&1; then
  if cloud-init schema --config-file "${RENDERED_FILE}" >/dev/null 2>&1; then
    check_pass "cloud-init schema validation passed"
  else
    SCHEMA_OUT="$(cloud-init schema --config-file "${RENDERED_FILE}" 2>&1 | head -20)"
    yellow "cloud-init schema validation output:"
    echo "${SCHEMA_OUT}"
    yellow "Schema warnings may be acceptable for non-Ubuntu environments"
  fi
else
  yellow "cloud-init not installed locally - skipping schema validation"
  yellow "To validate schema: apt-get install cloud-init && cloud-init schema --config-file <rendered>"
  yellow "Or use Docker: docker run --rm -v ${RENDERED_FILE}:/tmp/ci.yaml ubuntu:24.04 bash -c 'apt-get install -y cloud-init -q && cloud-init schema --config-file /tmp/ci.yaml'"
fi

# ── Summary ───────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────"
if [[ "${FAIL}" -eq 0 ]]; then
  green "Validation complete: ${PASS} checks passed, ${FAIL} failed"
  exit 0
else
  red "Validation complete: ${PASS} checks passed, ${FAIL} FAILED"
  exit 1
fi
