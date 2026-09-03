#!/usr/bin/env bash
# ============================================================
# Ixora Observability — Grafana Foundation Validation
# Phase 8.1 + Phase 8.2 + Phase 8.3 + Phase 8.4 + Phase 8.5 + Phase 8.6
#
# Phase 8.1 checks (1–6):
#   Validates that Grafana has started correctly and that all
#   provisioned datasources are available with stable UIDs.
#
# Phase 8.2 checks (7–12):
#   Validates dashboard folder names, D-07 JSON syntax, UID,
#   provisioning status, datasource references, and folder
#   assignment.
#
# Phase 8.4 checks (13–16):
#   Validates D-02 Smart Home Business dashboard:
#   13: JSON syntax valid.
#   14: UID stable (ixora-smart-home).
#   15: Provisioned in Grafana, placed in Business folder.
#   16: Datasource UID references (ixora-prometheus present,
#       no name-only references).
#
# Phase 8.3 global checks (25–26):
#   25: Dashboard UID uniqueness — every UID appears exactly once
#       across all provisioning directories.
#   26: Dashboard UID naming — every UID starts with "ixora-".
#
# Phase 8.5 checks (34–42):
#   Validates D-01 Platform Overview dashboard and cross-dashboard
#   conventions:
#   34: D-01 JSON syntax valid.
#   35: UID stable (ixora-platform) in JSON file.
#   36: D-01 provisioned in Grafana, placed in Overview folder.
#   37: Datasource UID references (ixora-prometheus, no name-only).
#   38: All dashboard links use UID-style URLs (no numeric IDs).
#   39: D-01 panel IDs unique within dashboard.
#   40: D-01 panel IDs respect reserved ranges (1–599).
#   41: Every non-row panel in D-01 contains a description.
#   42: Every non-row panel in D-01 contains a datasource UID.
#
# Phase 8.6 checks (43–48):
#   Navigation mesh and link quality checks:
#   43: Every specialized dashboard (D-02/D-04/D-05/D-06/D-07)
#       contains a link back to /d/ixora-platform.
#   44: All dashboard links follow the standard ordering
#       (D-01, D-02, D-04, D-05, D-06, D-07 — self excluded).
#   45: No duplicate dashboard links within any dashboard.
#   46: All dashboard-level links use keepTime=true.
#   47: No dashboard-level navigation link uses targetBlank=true.
#   48: Panel ID integrity — no duplicates, no non-positive IDs,
#       across all 6 provisioned dashboards. Range compliance is
#       documented in dashboard-conventions.md §8 (three schemes
#       coexist: scheme A for D-01/D-02, section-range-start for
#       D-04/D-05/D-06, legacy sequential for D-07).
#
# Phase 8.9 checks (68–78, 91–98):
#   Recording Rules & SLO Foundation structural integrity:
#   68: prometheus/rules/recording/ directory exists.
#   69: application.rules.yml exists and is valid YAML.
#   70: business.rules.yml exists and is valid YAML.
#   71: infrastructure.rules.yml exists and is valid YAML.
#   72: slo.rules.yml exists and is valid YAML.
#   73: docs/architecture/recording-rules-philosophy.md exists.
#   74: docs/architecture/slo-philosophy.md exists.
#   75: docs/specs/observability-foundation/mvp/recording-rules-foundation.md exists.
#   76: Catalog documented (REC-001 in foundation spec).
#   77: SLI definitions documented (SLI-001 in foundation spec).
#   78: Naming convention documented (ixora:http:error_rate:5m).
#
# Phase 8.8.6 checks (79–90):
#   Observability Infrastructure Hardening documentation integrity:
#   79: observability-hardening.md exists.
#   80: deployment-strategy.md exists.
#   81: backup-strategy.md exists.
#   82: storage-strategy.md exists.
#   83: future-cicd.md exists.
#   84: cloud-init-review.md exists.
#   85: app-platform-otel-integration.md exists.
#   86: Release deployment strategy documented (release-YYYY.MM.DD pattern).
#   87: Backup architecture covers Prometheus, Loki, Tempo, Grafana.
#   88: Hardening doc cross-references provisioning doc.
#   89: Reserved IP variable documented (observability_use_reserved_ip).
#   90: Single deploy script referenced (deploy-observability.sh).
#
# Usage:
#   ./validate.sh
#   GRAFANA_URL=http://localhost:3000 ./validate.sh
#
# Prerequisites:
#   - Grafana is running: docker compose up -d grafana
#   - curl is installed on the host
#   - python3 is available on the host
#   - GF_ADMIN_USER and GF_ADMIN_PASSWORD are set (or defaults used)
#
# Exit codes:
#   0  All checks passed
#   1  One or more checks failed
# ============================================================

set -euo pipefail

GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
GRAFANA_USER="${GF_ADMIN_USER:-admin}"
GRAFANA_PASS="${GF_ADMIN_PASSWORD:-}"
PASS_COUNT=0
FAIL_COUNT=0

# Script directory — used to locate dashboard JSON files for validation.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROVISIONING_DIR="${SCRIPT_DIR}/provisioning"

# ── helpers ──────────────────────────────────────────────────

green()  { printf "\033[0;32m✓ %s\033[0m\n" "$*"; }
red()    { printf "\033[0;31m✗ %s\033[0m\n" "$*"; }
yellow() { printf "\033[0;33m  %s\033[0m\n" "$*"; }

pass() { green "$1";  (( PASS_COUNT++ )) || true; }
fail() { red   "$1";  (( FAIL_COUNT++ )) || true; }

grafana_get() {
  local path="$1"
  curl --silent --fail \
    --user "${GRAFANA_USER}:${GRAFANA_PASS}" \
    "${GRAFANA_URL}${path}"
}

# ── check: admin password set ─────────────────────────────────

if [[ -z "${GRAFANA_PASS}" ]]; then
  fail "GF_ADMIN_PASSWORD is not set — cannot authenticate"
  echo ""
  echo "  Set it in .env and source it, or run:"
  echo "    GF_ADMIN_PASSWORD=<pass> ./validate.sh"
  exit 1
fi

echo ""
echo "Grafana Foundation Validation — Phase 8.1 + 8.2 + 8.3 + 8.4 + 8.5 + 8.6 + 8.7 + 8.8 + 8.9 (SLO)"
echo "Target: ${GRAFANA_URL}"
echo "────────────────────────────────────────────────"
echo ""

# ── 1. Health check ───────────────────────────────────────────

echo "1. Grafana health"
if grafana_get "/api/health" 2>/dev/null | grep -q '"database": "ok"'; then
  pass "Grafana is healthy (database: ok)"
else
  fail "Grafana health check failed — is the container running?"
  yellow "  docker compose up -d grafana"
  echo ""
  echo "────────────────────────────────────────────────"
  echo "FAIL: ${FAIL_COUNT} check(s) failed, ${PASS_COUNT} passed."
  exit 1
fi

# ── 2. Datasource UIDs ────────────────────────────────────────

echo ""
echo "2. Datasource UIDs (must be stable — never autogenerated)"

check_datasource() {
  local label="$1"
  local expected_uid="$2"
  local ds_json
  ds_json=$(grafana_get "/api/datasources/uid/${expected_uid}" 2>/dev/null || echo "")
  if echo "${ds_json}" | grep -q "\"uid\":\"${expected_uid}\""; then
    pass "${label} datasource: uid=${expected_uid}"
  else
    fail "${label} datasource uid '${expected_uid}' not found"
    yellow "  Check grafana/provisioning/datasources/datasources.yaml"
  fi
}

check_datasource "Prometheus" "ixora-prometheus"
check_datasource "Loki"       "ixora-loki"
check_datasource "Tempo"      "ixora-tempo"

# ── 3. Default datasource ─────────────────────────────────────

echo ""
echo "3. Default datasource"
DEFAULT_DS=$(grafana_get "/api/datasources" 2>/dev/null | \
  python3 -c "import sys,json; ds=[d for d in json.load(sys.stdin) if d.get('isDefault')]; print(ds[0]['uid'] if ds else 'none')" 2>/dev/null || echo "none")

if [[ "${DEFAULT_DS}" == "ixora-prometheus" ]]; then
  pass "Default datasource: ixora-prometheus (Prometheus)"
else
  fail "Default datasource is '${DEFAULT_DS}', expected 'ixora-prometheus'"
fi

# ── 4. Datasource connectivity ────────────────────────────────

echo ""
echo "4. Datasource connectivity (proxy health)"

check_ds_health() {
  local label="$1"
  local uid="$2"
  # Use curl without --fail so we get the body even for 4xx responses.
  # Some plugins (e.g. Tempo) return 404 "notImplemented" — treat as pass.
  local raw
  raw=$(curl --silent \
    --user "${GRAFANA_USER}:${GRAFANA_PASS}" \
    "${GRAFANA_URL}/api/datasources/uid/${uid}/health" 2>/dev/null || echo '{"status":"error"}')
  local result
  result=$(echo "${raw}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status','unknown'))" 2>/dev/null || echo "error")
  if [[ "${result}" == "OK" ]]; then
    pass "${label} connectivity: OK"
  elif echo "${raw}" | grep -qi "notImplemented\|not implemented"; then
    # Tempo plugin does not implement the /health endpoint in Grafana 11.
    # The datasource was provisioned correctly; backend connectivity is
    # verified separately by Grafana when the datasource is saved.
    pass "${label} connectivity: health endpoint not supported by plugin (datasource provisioned)"
  else
    fail "${label} connectivity: ${result} — is the backend running?"
    yellow "  docker compose up -d prometheus loki tempo"
  fi
}

check_ds_health "Prometheus" "ixora-prometheus"
check_ds_health "Loki"       "ixora-loki"
check_ds_health "Tempo"      "ixora-tempo"

# ── 5. Provisioning is idempotent ─────────────────────────────

echo ""
echo "5. Provisioning locked (editable: false)"

check_ds_readonly() {
  local label="$1"
  local uid="$2"
  local readonly_val
  readonly_val=$(grafana_get "/api/datasources/uid/${uid}" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(str(d.get('readOnly', False)).lower())" 2>/dev/null || echo "false")
  if [[ "${readonly_val}" == "true" ]]; then
    pass "${label}: readOnly=true (changes require provisioning file update)"
  else
    fail "${label}: readOnly=false — datasource may be edited via UI (check editable: false in YAML)"
  fi
}

check_ds_readonly "Prometheus" "ixora-prometheus"
check_ds_readonly "Loki"       "ixora-loki"
check_ds_readonly "Tempo"      "ixora-tempo"

# ── 6. No manual datasources ──────────────────────────────────

echo ""
echo "6. No unprovisioned datasources"
DS_COUNT=$(grafana_get "/api/datasources" 2>/dev/null | \
  python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")

if [[ "${DS_COUNT}" -eq 3 ]]; then
  pass "Datasource count: 3 (Prometheus + Loki + Tempo — no extras)"
else
  fail "Datasource count: ${DS_COUNT} (expected 3) — unprovisioned datasources present?"
  yellow "  Remove manually-created datasources from the Grafana UI"
fi

# ── 7. Folder existence and names (Phase 8.2) ────────────────
# Grafana 11.3 creates dashboard folders with auto-generated UIDs regardless
# of the folderUID setting in providers.yaml (folderUID only MATCHES existing
# folders, it does not CREATE them with a specific UID).
# Folder UIDs are therefore stable within a running Grafana instance but
# reset on Grafana data volume recreation.
#
# Critical stable identifiers (never change):
#   Dashboard UIDs  — defined in JSON, immutable (e.g. ixora-collector)
#   Datasource UIDs — defined in datasources.yaml, immutable (e.g. ixora-prometheus)
#
# Folder names (stable, human-readable):
#   Infrastructure, Application, Business, Overview
#
# This check verifies folder NAMES exist. The auto-generated UIDs are
# documented as a known limitation in dashboard-d07-infrastructure.md.

echo ""
echo "7. Dashboard folder names (Phase 8.2)"

FOLDERS_JSON=$(curl --silent \
  --user "${GRAFANA_USER}:${GRAFANA_PASS}" \
  "${GRAFANA_URL}/api/folders?limit=100" 2>/dev/null || echo "[]")

check_folder_exists() {
  local title="$1"
  local folder_uid
  folder_uid=$(echo "${FOLDERS_JSON}" | python3 -c "
import sys, json
folders = json.load(sys.stdin)
for f in folders:
    if f.get('title','') == '${title}':
        print(f.get('uid',''))
        break
" 2>/dev/null || echo "")
  if [[ -n "${folder_uid}" ]]; then
    pass "Folder '${title}': exists (uid=${folder_uid})"
  else
    fail "Folder '${title}': not found — is the dashboard provider running with at least one JSON file?"
  fi
}

check_folder_exists "Infrastructure"
check_folder_exists "Application"
check_folder_exists "Business"
check_folder_exists "Overview"

# ── 8. Dashboard JSON syntax ─────────────────────────────────

echo ""
echo "8. Dashboard JSON syntax validation"

check_json_syntax() {
  local label="$1"
  local file="$2"
  if [[ ! -f "${file}" ]]; then
    fail "${label}: file not found at ${file}"
    return
  fi
  if python3 -m json.tool "${file}" > /dev/null 2>&1; then
    pass "${label}: valid JSON"
  else
    fail "${label}: invalid JSON syntax"
    yellow "  Validate with: python3 -m json.tool ${file}"
  fi
}

check_json_syntax "D-07 Infrastructure" \
  "${PROVISIONING_DIR}/dashboards/infrastructure/d07-infrastructure.json"

# ── 9. Dashboard UID in JSON ──────────────────────────────────

echo ""
echo "9. Dashboard UID stability (no autogenerated UIDs)"

check_dashboard_uid_in_file() {
  local label="$1"
  local file="$2"
  local expected_uid="$3"
  if [[ ! -f "${file}" ]]; then
    fail "${label}: file not found"
    return
  fi
  local actual_uid
  actual_uid=$(python3 -c "
import json, sys
with open('${file}') as f:
    d = json.load(f)
print(d.get('uid', ''))
" 2>/dev/null || echo "")
  if [[ "${actual_uid}" == "${expected_uid}" ]]; then
    pass "${label}: uid=${expected_uid} (stable)"
  else
    fail "${label}: uid='${actual_uid}', expected '${expected_uid}'"
  fi
}

check_dashboard_uid_in_file "D-07 JSON file" \
  "${PROVISIONING_DIR}/dashboards/infrastructure/d07-infrastructure.json" \
  "ixora-collector"

# ── 10. Dashboard provisioned in Grafana ─────────────────────

echo ""
echo "10. Dashboard provisioned and accessible"

check_dashboard_provisioned() {
  local label="$1"
  local uid="$2"
  local expected_folder_title="$3"
  local raw
  raw=$(curl --silent \
    --user "${GRAFANA_USER}:${GRAFANA_PASS}" \
    "${GRAFANA_URL}/api/dashboards/uid/${uid}" 2>/dev/null || echo "")

  local provisioned
  provisioned=$(echo "${raw}" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('meta', {}).get('provisioned', False))
" 2>/dev/null || echo "False")

  local folder_title
  folder_title=$(echo "${raw}" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('meta', {}).get('folderTitle', ''))
" 2>/dev/null || echo "")

  local dashboard_uid
  dashboard_uid=$(echo "${raw}" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('dashboard', {}).get('uid', ''))
" 2>/dev/null || echo "")

  if [[ "${dashboard_uid}" != "${uid}" ]]; then
    fail "${label}: dashboard uid='${uid}' not found in Grafana"
    yellow "  Check Grafana logs: docker compose logs grafana --tail=50"
    return
  fi
  pass "${label}: found uid=${uid}"

  if [[ "${provisioned}" == "True" ]]; then
    pass "${label}: provisioned=true (file-based provisioning active)"
  else
    fail "${label}: provisioned=false — dashboard was created manually, not via provisioning"
  fi

  if [[ "${folder_title}" == "${expected_folder_title}" ]]; then
    pass "${label}: folder='${expected_folder_title}'"
  else
    fail "${label}: folder='${folder_title}', expected '${expected_folder_title}'"
  fi
}

check_dashboard_provisioned "D-07 Infrastructure" "ixora-collector" "Infrastructure"

# ── 11. Dashboard datasource references ──────────────────────

echo ""
echo "11. Dashboard datasource UID references (no hardcoded names)"

check_dashboard_datasources() {
  local label="$1"
  local file="$2"
  if [[ ! -f "${file}" ]]; then
    fail "${label}: file not found"
    return
  fi

  # Ensure no datasource is referenced by name (type + name pattern).
  # All datasource references must use the uid field.
  local bad_ref
  bad_ref=$(python3 -c "
import json, sys
with open('${file}') as f:
    content = f.read()
# Check that 'Prometheus', 'Loki', 'Tempo' are not used as datasource names
# (they would appear as '\''name\'' field values, not '\''uid'\'').
import re
# Find all datasource objects and check they have uid and not just name
bad = []
d = json.loads(content)
def scan(obj):
    if isinstance(obj, dict):
        if obj.get('type') in ('prometheus','loki','tempo') and 'uid' not in obj:
            bad.append(str(obj))
        for v in obj.values():
            scan(v)
    elif isinstance(obj, list):
        for v in obj:
            scan(v)
scan(d)
print(len(bad))
" 2>/dev/null || echo "0")

  if [[ "${bad_ref}" == "0" ]]; then
    pass "${label}: all datasource references use UID (no name-only references)"
  else
    fail "${label}: ${bad_ref} datasource reference(s) missing uid field"
  fi

  # Verify the three expected datasource UIDs are present.
  local uids_found
  uids_found=$(python3 -c "
import json, sys
with open('${file}') as f:
    content = f.read()
expected = {'ixora-prometheus', 'ixora-loki', 'ixora-tempo'}
found = set()
import re
for uid in re.findall(r'\"uid\":\s*\"([^\"]+)\"', content):
    if uid in expected:
        found.add(uid)
missing = expected - found
# For D-07 only Prometheus is actively used; Loki+Tempo are defined in datasource vars only.
# Warn but don't fail if only Prometheus is referenced (D-07 is Prometheus-only).
print(','.join(sorted(found)))
" 2>/dev/null || echo "")

  if echo "${uids_found}" | grep -q "ixora-prometheus"; then
    pass "${label}: ixora-prometheus referenced (primary datasource for D-07)"
  else
    fail "${label}: ixora-prometheus not found in datasource references"
  fi
}

check_dashboard_datasources "D-07 Infrastructure" \
  "${PROVISIONING_DIR}/dashboards/infrastructure/d07-infrastructure.json"

# ── 12. Dashboard folder (post-provision) ────────────────────

echo ""
echo "12. Dashboard folder assignment (post-provision)"

DASH_META=$(curl --silent \
  --user "${GRAFANA_USER}:${GRAFANA_PASS}" \
  "${GRAFANA_URL}/api/dashboards/uid/ixora-collector" 2>/dev/null | \
  python3 -c "
import sys, json
d = json.load(sys.stdin)
meta = d.get('meta', {})
print(meta.get('folderTitle', ''))
print(meta.get('folderUid', ''))
" 2>/dev/null || echo "")

DASH_FOLDER_TITLE=$(echo "${DASH_META}" | sed -n '1p')
DASH_FOLDER_UID=$(echo "${DASH_META}" | sed -n '2p')

if [[ "${DASH_FOLDER_TITLE}" == "Infrastructure" ]]; then
  pass "D-07: correctly placed in 'Infrastructure' folder"
else
  fail "D-07: in folder '${DASH_FOLDER_TITLE}', expected 'Infrastructure'"
fi

# Folder UID is auto-generated by Grafana 11.3 (known limitation — see spec).
# We report it but do not fail on it.
yellow "D-07 folderUID=${DASH_FOLDER_UID} (auto-generated; see dashboard-d07-infrastructure.md §known-limitations)"

# ── 13. D-02 Smart Home Business Dashboard — JSON syntax ─────

echo ""
echo "13. D-02 Smart Home Business Dashboard JSON syntax"

check_json_syntax "D-02 Smart Home" \
  "${PROVISIONING_DIR}/dashboards/business/d02-smart-home.json"

# ── 14. D-02 Smart Home Business Dashboard — UID in JSON ─────

echo ""
echo "14. D-02 Smart Home Business Dashboard UID (ixora-smart-home)"

check_dashboard_uid_in_file "D-02 Smart Home JSON file" \
  "${PROVISIONING_DIR}/dashboards/business/d02-smart-home.json" \
  "ixora-smart-home"

# ── 15. D-02 Smart Home Business Dashboard — provisioned ─────

echo ""
echo "15. D-02 Smart Home Business Dashboard provisioned in Grafana"

check_dashboard_provisioned "D-02 Smart Home" "ixora-smart-home" "Business"

# ── 16. D-02 Smart Home Business Dashboard — datasources ─────

echo ""
echo "16. D-02 Smart Home Business Dashboard datasource UID references"

check_dashboard_datasources "D-02 Smart Home" \
  "${PROVISIONING_DIR}/dashboards/business/d02-smart-home.json"

# ── 25. Dashboard UID uniqueness ──────────────────────────
# Every dashboard UID must appear exactly once across all
# provisioning directories. Duplicate UIDs cause Grafana to
# silently overwrite one dashboard with another on startup.

echo ""
echo "25. Dashboard UID uniqueness (no duplicates across all provisioning dirs)"

UID_CHECK=$(python3 -c "
import json, os, sys

provisioning = '${PROVISIONING_DIR}/dashboards'
uid_map = {}

for root, dirs, files in os.walk(provisioning):
    for fname in sorted(files):
        if not fname.endswith('.json'):
            continue
        fpath = os.path.join(root, fname)
        try:
            with open(fpath) as f:
                d = json.load(f)
            uid = d.get('uid', '')
            if uid:
                uid_map.setdefault(uid, []).append(fpath)
        except Exception as e:
            print(f'error: cannot parse {fpath}: {e}', file=sys.stderr)

duplicates = {u: paths for u, paths in uid_map.items() if len(paths) > 1}

if duplicates:
    for uid, paths in sorted(duplicates.items()):
        print(f'FAIL: UID \"{uid}\" appears {len(paths)} times: {\" | \".join(paths)}')
else:
    print(f'PASS: {len(uid_map)} dashboard(s) — all UIDs unique')
" 2>/dev/null || echo "FAIL: python3 UID uniqueness check failed")

if echo "${UID_CHECK}" | grep -q "^PASS:"; then
  pass "${UID_CHECK#PASS: }"
else
  fail "${UID_CHECK#FAIL: }"
fi

# ── 26. Dashboard UID naming convention ──────────────────
# Every dashboard UID must begin with "ixora-".
# Enforces the naming convention from dashboard-conventions.md §1.

echo ""
echo "26. Dashboard UID naming convention (all UIDs must start with 'ixora-')"

NAMING_CHECK=$(python3 -c "
import json, os, sys

provisioning = '${PROVISIONING_DIR}/dashboards'
bad = []
total = 0

for root, dirs, files in os.walk(provisioning):
    for fname in sorted(files):
        if not fname.endswith('.json'):
            continue
        fpath = os.path.join(root, fname)
        try:
            with open(fpath) as f:
                d = json.load(f)
            uid = d.get('uid', '')
            if uid:
                total += 1
                if not uid.startswith('ixora-'):
                    bad.append(f'\"{uid}\" ({fname})')
        except Exception as e:
            print(f'error: {fpath}: {e}', file=sys.stderr)

if bad:
    print(f'FAIL: {len(bad)} UID(s) do not start with ixora-: {\" | \".join(bad)}')
else:
    print(f'PASS: all {total} dashboard UID(s) start with ixora-')
" 2>/dev/null || echo "FAIL: python3 UID naming check failed")

if echo "${NAMING_CHECK}" | grep -q "^PASS:"; then
  pass "${NAMING_CHECK#PASS: }"
else
  fail "${NAMING_CHECK#FAIL: }"
fi
# ── 34. D-01 Platform Overview — JSON syntax ─────────────────

echo ""
echo "34. D-01 Platform Overview JSON syntax"

check_json_syntax "D-01 Platform Overview" \
  "${PROVISIONING_DIR}/dashboards/overview/d01-platform-overview.json"

# ── 35. D-01 Platform Overview — UID in JSON ─────────────────

echo ""
echo "35. D-01 Platform Overview UID (ixora-platform)"

check_dashboard_uid_in_file "D-01 Platform Overview JSON file" \
  "${PROVISIONING_DIR}/dashboards/overview/d01-platform-overview.json" \
  "ixora-platform"

# ── 36. D-01 Platform Overview — provisioned + folder ────────
# Single combined check: uid found in Grafana, provisioned=true,
# and placed in the Overview folder.

echo ""
echo "36. D-01 Platform Overview provisioned in Grafana (Overview folder)"

D01_RESULT=$(python3 -c "
import json, subprocess, sys

url  = '${GRAFANA_URL}'
user = '${GRAFANA_USER}'
pw   = '${GRAFANA_PASS}'

try:
    out = subprocess.check_output([
        'curl', '--silent', '--fail',
        '--user', f'{user}:{pw}',
        f'{url}/api/dashboards/uid/ixora-platform'
    ], stderr=subprocess.DEVNULL)
    d = json.loads(out)
except Exception as e:
    print(f'FAIL: cannot fetch ixora-platform from Grafana: {e}')
    sys.exit(0)

uid = d.get('dashboard', {}).get('uid', '')
provisioned = d.get('meta', {}).get('provisioned', False)
folder = d.get('meta', {}).get('folderTitle', '')

if uid != 'ixora-platform':
    print(f'FAIL: dashboard uid=\"{uid}\", expected ixora-platform')
elif not provisioned:
    print('FAIL: provisioned=false (dashboard was created manually, not via provisioning file)')
elif folder != 'Overview':
    print(f'FAIL: folder=\"{folder}\", expected Overview')
else:
    print('PASS: ixora-platform provisioned=true in Overview folder')
" 2>/dev/null || echo "FAIL: python3 check failed")

if echo "${D01_RESULT}" | grep -q "^PASS:"; then
  pass "${D01_RESULT#PASS: }"
else
  fail "${D01_RESULT#FAIL: }"
fi

# ── 37. D-01 Platform Overview — datasource UID references ───
# Single combined check: no name-only datasource references AND
# ixora-prometheus is present as the primary datasource.

echo ""
echo "37. D-01 Platform Overview datasource UID references"

D01_DS_RESULT=$(python3 -c "
import json, sys

fpath = '${PROVISIONING_DIR}/dashboards/overview/d01-platform-overview.json'
try:
    with open(fpath) as f:
        d = json.load(f)
except Exception as e:
    print(f'FAIL: cannot open {fpath}: {e}')
    sys.exit(0)

bad = []
def scan(obj):
    if isinstance(obj, dict):
        if obj.get('type') in ('prometheus','loki','tempo') and 'uid' not in obj:
            bad.append(str(obj))
        for v in obj.values():
            scan(v)
    elif isinstance(obj, list):
        for v in obj:
            scan(v)
scan(d)

import re
content = json.dumps(d)
has_prometheus = 'ixora-prometheus' in re.findall(r'\"uid\":\s*\"([^\"]+)\"', content)

if bad:
    print(f'FAIL: {len(bad)} datasource reference(s) missing uid field')
elif not has_prometheus:
    print('FAIL: ixora-prometheus not found in datasource uid references')
else:
    print('PASS: all datasource references use UID, ixora-prometheus present')
" 2>/dev/null || echo "FAIL: python3 datasource check failed")

if echo "${D01_DS_RESULT}" | grep -q "^PASS:"; then
  pass "${D01_DS_RESULT#PASS: }"
else
  fail "${D01_DS_RESULT#FAIL: }"
fi

# ── 38. Dashboard links use UID-style URLs ────────────────────
# All links across all provisioned dashboards must use /d/ixora-*
# style UIDs. Numeric IDs (e.g. /d/123) break when Grafana
# data volume is recreated or on a fresh install.

echo ""
echo "38. Dashboard links use UID-style URLs (no /d/<numeric-id>)"

LINK_CHECK=$(python3 -c "
import json, os, re, sys

provisioning = '${PROVISIONING_DIR}/dashboards'
bad = []

for root, dirs, files in os.walk(provisioning):
    for fname in sorted(files):
        if not fname.endswith('.json'):
            continue
        fpath = os.path.join(root, fname)
        try:
            with open(fpath) as f:
                content = f.read()
            numeric = re.findall(r'/d/[0-9]+', content)
            if numeric:
                bad.append(f'{fname}: {numeric}')
        except Exception as e:
            bad.append(f'error reading {fname}: {e}')

if bad:
    print('FAIL: numeric dashboard IDs found in links: ' + ' | '.join(bad))
else:
    print('PASS: all dashboard links use UID-style URLs')
" 2>/dev/null || echo "FAIL: python3 link check failed")

if echo "${LINK_CHECK}" | grep -q "^PASS:"; then
  pass "${LINK_CHECK#PASS: }"
else
  fail "${LINK_CHECK#FAIL: }"
fi

# ── 39. D-01 panel IDs unique within dashboard ───────────────

echo ""
echo "39. D-01 panel IDs unique within dashboard"

PANEL_ID_UNIQ=$(python3 -c "
import json, sys

fpath = '${PROVISIONING_DIR}/dashboards/overview/d01-platform-overview.json'
try:
    with open(fpath) as f:
        d = json.load(f)
except Exception as e:
    print(f'FAIL: cannot open file: {e}')
    sys.exit(0)

ids = [p['id'] for p in d.get('panels', []) if 'id' in p]
seen = {}
for i in ids:
    seen[i] = seen.get(i, 0) + 1
dupes = [i for i, c in seen.items() if c > 1]

if dupes:
    print(f'FAIL: duplicate panel IDs: {dupes}')
else:
    print(f'PASS: {len(ids)} panel IDs — all unique')
" 2>/dev/null || echo "FAIL: python3 panel ID check failed")

if echo "${PANEL_ID_UNIQ}" | grep -q "^PASS:"; then
  pass "${PANEL_ID_UNIQ#PASS: }"
else
  fail "${PANEL_ID_UNIQ#FAIL: }"
fi

# ── 40. D-01 panel IDs respect reserved ranges ───────────────
# Allowed ranges per dashboard-conventions.md §8:
#   1–99   row headers
#   100–199 health
#   200–299 throughput/business
#   300–399 errors/application
#   400–499 performance/infrastructure
#   500–599 business relationships/navigation

echo ""
echo "40. D-01 panel IDs respect reserved ranges (1–599)"

PANEL_RANGE=$(python3 -c "
import json, sys

fpath = '${PROVISIONING_DIR}/dashboards/overview/d01-platform-overview.json'
try:
    with open(fpath) as f:
        d = json.load(f)
except Exception as e:
    print(f'FAIL: cannot open file: {e}')
    sys.exit(0)

panels = d.get('panels', [])
bad = []
for p in panels:
    pid = p.get('id', -1)
    ptype = p.get('type', '')
    if ptype == 'row':
        if not (1 <= pid <= 99):
            bad.append(f'row panel id={pid} (expected 1–99)')
    else:
        if not (100 <= pid <= 599):
            bad.append(f'panel id={pid} (expected 100–599)')

if bad:
    print('FAIL: out-of-range panel IDs: ' + ' | '.join(bad))
else:
    total = len(panels)
    print(f'PASS: all {total} panels have IDs within reserved ranges (rows 1–99, content 100–599)')
" 2>/dev/null || echo "FAIL: python3 range check failed")

if echo "${PANEL_RANGE}" | grep -q "^PASS:"; then
  pass "${PANEL_RANGE#PASS: }"
else
  fail "${PANEL_RANGE#FAIL: }"
fi

# ── 41. D-01 every non-row panel has description ─────────────

echo ""
echo "41. D-01 every non-row panel contains description"

PANEL_DESC=$(python3 -c "
import json, sys

fpath = '${PROVISIONING_DIR}/dashboards/overview/d01-platform-overview.json'
try:
    with open(fpath) as f:
        d = json.load(f)
except Exception as e:
    print(f'FAIL: cannot open file: {e}')
    sys.exit(0)

bad = []
for p in d.get('panels', []):
    if p.get('type') == 'row':
        continue
    desc = p.get('description', '').strip()
    if not desc:
        bad.append(f'id={p[\"id\"]} title=\"{p.get(\"title\",\"\")}\"')

if bad:
    print(f'FAIL: {len(bad)} panel(s) missing description: ' + ' | '.join(bad))
else:
    content_count = len([p for p in d.get('panels', []) if p.get('type') != 'row'])
    print(f'PASS: all {content_count} non-row panels have a description')
" 2>/dev/null || echo "FAIL: python3 description check failed")

if echo "${PANEL_DESC}" | grep -q "^PASS:"; then
  pass "${PANEL_DESC#PASS: }"
else
  fail "${PANEL_DESC#FAIL: }"
fi

# ── 42. D-01 every non-row panel has datasource UID ──────────

echo ""
echo "42. D-01 every non-row panel contains datasource UID"

PANEL_DS=$(python3 -c "
import json, sys

fpath = '${PROVISIONING_DIR}/dashboards/overview/d01-platform-overview.json'
try:
    with open(fpath) as f:
        d = json.load(f)
except Exception as e:
    print(f'FAIL: cannot open file: {e}')
    sys.exit(0)

bad = []
for p in d.get('panels', []):
    if p.get('type') == 'row':
        continue
    ds = p.get('datasource', {})
    uid = ds.get('uid', '').strip() if isinstance(ds, dict) else ''
    if not uid:
        bad.append(f'id={p[\"id\"]} title=\"{p.get(\"title\",\"\")}\"')

if bad:
    print(f'FAIL: {len(bad)} panel(s) missing datasource uid: ' + ' | '.join(bad))
else:
    content_count = len([p for p in d.get('panels', []) if p.get('type') != 'row'])
    print(f'PASS: all {content_count} non-row panels have datasource uid')
" 2>/dev/null || echo "FAIL: python3 datasource uid check failed")

if echo "${PANEL_DS}" | grep -q "^PASS:"; then
  pass "${PANEL_DS#PASS: }"
else
  fail "${PANEL_DS#FAIL: }"
fi

# ── 43. Back-link to D-01 in every specialized dashboard ─────
# D-02, D-04, D-05, D-06, D-07 must each contain a navigation link
# pointing to /d/ixora-platform.
# D-01 itself is excluded (it IS the Platform Overview).

echo ""
echo "43. Every specialized dashboard contains a back-link to /d/ixora-platform"

BACKLINK_CHECK=$(python3 -c "
import json, os, sys

provisioning = '${PROVISIONING_DIR}/dashboards'
missing = []

# Map file basename -> uid for all specialized dashboards
for root, dirs, files in os.walk(provisioning):
    for fname in sorted(files):
        if not fname.endswith('.json'):
            continue
        fpath = os.path.join(root, fname)
        try:
            with open(fpath) as f:
                d = json.load(f)
        except Exception as e:
            missing.append(f'cannot parse {fname}: {e}')
            continue
        uid = d.get('uid', '')
        if uid == 'ixora-platform':
            continue  # D-01 excluded
        links = d.get('links', [])
        urls = [l.get('url','') for l in links if isinstance(l, dict)]
        if '/d/ixora-platform' not in urls:
            missing.append(f'uid={uid} ({fname})')

if missing:
    print('FAIL: missing D-01 back-link: ' + ' | '.join(missing))
else:
    print('PASS: all 6 specialized dashboards link back to /d/ixora-platform')
" 2>/dev/null || echo "FAIL: python3 back-link check failed")

if echo "${BACKLINK_CHECK}" | grep -q "^PASS:"; then
  pass "${BACKLINK_CHECK#PASS: }"
else
  fail "${BACKLINK_CHECK#FAIL: }"
fi

# ── 44. Dashboard links follow standard ordering ─────────────
# Standard order (self excluded):
#   /d/ixora-platform, /d/ixora-smart-home, /d/ixora-queue,
#   /d/ixora-http, /d/ixora-scheduler, /d/ixora-collector

echo ""
echo "44. Dashboard links follow standard ordering (D-01→D-08→D-02→…→D-07)"

ORDER_CHECK=$(python3 -c "
import json, os, sys

provisioning = '${PROVISIONING_DIR}/dashboards'

STANDARD_ORDER = [
    '/d/ixora-platform',
    '/d/ixora-slo',
    '/d/ixora-smart-home',
    '/d/ixora-push',
    '/d/ixora-queue',
    '/d/ixora-http',
    '/d/ixora-scheduler',
    '/d/ixora-collector',
]

bad = []

for root, dirs, files in os.walk(provisioning):
    for fname in sorted(files):
        if not fname.endswith('.json'):
            continue
        fpath = os.path.join(root, fname)
        try:
            with open(fpath) as f:
                d = json.load(f)
        except Exception:
            continue
        uid = d.get('uid', '')
        self_url = f'/d/{uid}' if uid else None
        links = d.get('links', [])
        actual_urls = [l.get('url','') for l in links if isinstance(l, dict)]
        # Expected: STANDARD_ORDER minus self
        expected = [u for u in STANDARD_ORDER if u != self_url]
        if actual_urls != expected:
            bad.append(f'uid={uid} ({fname}): got {actual_urls}, expected {expected}')

if bad:
    print('FAIL: incorrect link ordering: ' + ' | '.join(bad))
else:
    print('PASS: all 8 dashboards follow standard link ordering')
" 2>/dev/null || echo "FAIL: python3 order check failed")

if echo "${ORDER_CHECK}" | grep -q "^PASS:"; then
  pass "${ORDER_CHECK#PASS: }"
else
  fail "${ORDER_CHECK#FAIL: }"
fi

# ── 45. No duplicate dashboard links ─────────────────────────

echo ""
echo "45. No duplicate dashboard links within any dashboard"

DEDUP_CHECK=$(python3 -c "
import json, os, sys

provisioning = '${PROVISIONING_DIR}/dashboards'
bad = []

for root, dirs, files in os.walk(provisioning):
    for fname in sorted(files):
        if not fname.endswith('.json'):
            continue
        fpath = os.path.join(root, fname)
        try:
            with open(fpath) as f:
                d = json.load(f)
        except Exception:
            continue
        uid = d.get('uid', '')
        links = d.get('links', [])
        urls = [l.get('url','') for l in links if isinstance(l, dict)]
        seen = {}
        for u in urls:
            seen[u] = seen.get(u, 0) + 1
        dupes = [u for u, c in seen.items() if c > 1]
        if dupes:
            bad.append(f'uid={uid} ({fname}): duplicate urls {dupes}')

if bad:
    print('FAIL: duplicate links found: ' + ' | '.join(bad))
else:
    print('PASS: no duplicate dashboard links in any dashboard')
" 2>/dev/null || echo "FAIL: python3 dedup check failed")

if echo "${DEDUP_CHECK}" | grep -q "^PASS:"; then
  pass "${DEDUP_CHECK#PASS: }"
else
  fail "${DEDUP_CHECK#FAIL: }"
fi

# ── 46. All dashboard links use keepTime=true ─────────────────

echo ""
echo "46. All dashboard-level links use keepTime=true"

KEEPTIME_CHECK=$(python3 -c "
import json, os, sys

provisioning = '${PROVISIONING_DIR}/dashboards'
bad = []

for root, dirs, files in os.walk(provisioning):
    for fname in sorted(files):
        if not fname.endswith('.json'):
            continue
        fpath = os.path.join(root, fname)
        try:
            with open(fpath) as f:
                d = json.load(f)
        except Exception:
            continue
        uid = d.get('uid', '')
        links = d.get('links', [])
        for l in links:
            if not isinstance(l, dict):
                continue
            if not l.get('keepTime', False):
                bad.append(f'uid={uid} ({fname}): link \"{l.get(\"title\",\"\")}\" has keepTime=false/missing')

if bad:
    print('FAIL: links missing keepTime=true: ' + ' | '.join(bad))
else:
    total = sum(len(json.load(open(os.path.join(r,f))).get('links',[])) for r,_,fs in os.walk(provisioning) for f in fs if f.endswith('.json') and os.path.isfile(os.path.join(r,f)))
    print(f'PASS: all dashboard-level links use keepTime=true')
" 2>/dev/null || echo "FAIL: python3 keepTime check failed")

if echo "${KEEPTIME_CHECK}" | grep -q "^PASS:"; then
  pass "${KEEPTIME_CHECK#PASS: }"
else
  fail "${KEEPTIME_CHECK#FAIL: }"
fi

# ── 47. No navigation link uses targetBlank=true ─────────────

echo ""
echo "47. No dashboard navigation link uses targetBlank=true"

TARGETBLANK_CHECK=$(python3 -c "
import json, os, sys

provisioning = '${PROVISIONING_DIR}/dashboards'
bad = []

for root, dirs, files in os.walk(provisioning):
    for fname in sorted(files):
        if not fname.endswith('.json'):
            continue
        fpath = os.path.join(root, fname)
        try:
            with open(fpath) as f:
                d = json.load(f)
        except Exception:
            continue
        uid = d.get('uid', '')
        links = d.get('links', [])
        for l in links:
            if not isinstance(l, dict):
                continue
            if l.get('targetBlank', False):
                bad.append(f'uid={uid} ({fname}): link \"{l.get(\"title\",\"\")}\" has targetBlank=true')

if bad:
    print('FAIL: dashboard navigation links with targetBlank=true: ' + ' | '.join(bad))
else:
    print('PASS: no dashboard navigation link uses targetBlank=true')
" 2>/dev/null || echo "FAIL: python3 targetBlank check failed")

if echo "${TARGETBLANK_CHECK}" | grep -q "^PASS:"; then
  pass "${TARGETBLANK_CHECK#PASS: }"
else
  fail "${TARGETBLANK_CHECK#FAIL: }"
fi

# ── 48. Panel ID integrity across all dashboards ─────────────
# Checks for every provisioned dashboard JSON file:
#   a) No duplicate panel IDs within any dashboard.
#   b) No panel ID <= 0.
#
# Range compliance notes (per dashboard-conventions.md §8):
#   - D-01, D-02: row IDs 1–5 (scheme A), content IDs 100–599.
#   - D-04, D-05, D-06: row IDs are section-range starts
#     (1 for Health, 200/300/400/500 for other sections) — this
#     is the "section-range-start" scheme explicitly allowed in
#     dashboard-conventions.md §8.
#   - D-07: predates the ID convention (Phase 8.2). Uses sequential
#     IDs 1–44. Legacy behaviour — duplicate check only.
# All three schemes are valid. Only duplicates and non-positive
# IDs constitute a defect.

echo ""
echo "48. Panel ID integrity (no duplicates, positive IDs) — all 8 dashboards"

PANEL_INTEGRITY=$(python3 -c "
import json, os, sys

provisioning = '${PROVISIONING_DIR}/dashboards'
bad = []
total_dashboards = 0

for root, dirs, files in os.walk(provisioning):
    for fname in sorted(files):
        if not fname.endswith('.json'):
            continue
        fpath = os.path.join(root, fname)
        try:
            with open(fpath) as f:
                d = json.load(f)
        except Exception as e:
            bad.append(f'cannot parse {fname}: {e}')
            continue

        total_dashboards += 1
        uid = d.get('uid', fname)
        panels = d.get('panels', [])

        # Rule a: no duplicate IDs within dashboard
        ids = [p.get('id') for p in panels if 'id' in p]
        seen = {}
        for pid in ids:
            seen[pid] = seen.get(pid, 0) + 1
        dupes = [pid for pid, c in seen.items() if c > 1]
        if dupes:
            bad.append(f'{fname} (uid={uid}): duplicate panel IDs {dupes}')

        # Rule b: no ID <= 0
        for p in panels:
            pid = p.get('id')
            if pid is not None and pid <= 0:
                bad.append(f'{fname} (uid={uid}): non-positive panel ID {pid}')

if bad:
    print('FAIL: panel ID issues: ' + ' | '.join(bad))
else:
    print(f'PASS: panel IDs valid across all {total_dashboards} dashboards (no duplicates, all IDs positive)')
" 2>/dev/null || echo "FAIL: python3 panel integrity check failed")

if echo "${PANEL_INTEGRITY}" | grep -q "^PASS:"; then
  pass "${PANEL_INTEGRITY#PASS: }"
else
  fail "${PANEL_INTEGRITY#FAIL: }"
fi

# ── 49. D-03 Push Notifications — JSON file exists ───────────

echo ""
echo "49. D-03 Push Notifications dashboard JSON file exists"

D03_PATH="${PROVISIONING_DIR}/dashboards/business/d03-push.json"

if [ -f "${D03_PATH}" ]; then
  pass "D-03 Push Notifications JSON file found: d03-push.json"
else
  fail "D-03 Push Notifications JSON file not found: ${D03_PATH}"
fi

# ── 50. D-03 UID equals ixora-push ────────────────────────────

echo ""
echo "50. D-03 Push Notifications UID equals ixora-push"

if [ -f "${D03_PATH}" ]; then
  D03_UID=$(python3 -c "import json; print(json.load(open('${D03_PATH}')).get('uid','MISSING'))" 2>/dev/null || echo "PARSE_ERROR")
  if [ "${D03_UID}" = "ixora-push" ]; then
    pass "D-03 Push Notifications JSON file: uid=ixora-push (stable)"
  else
    fail "D-03 Push Notifications: uid='${D03_UID}' (expected ixora-push)"
  fi
else
  fail "D-03 Push Notifications: cannot check UID — JSON file missing"
fi

# ── 51. D-03 provisioned in Grafana — Business folder ────────

echo ""
echo "51. D-03 Push Notifications provisioned in Grafana (Business folder)"

D03_API=$(curl -sf -u "admin:${GF_ADMIN_PASSWORD}" "${GRAFANA_URL}/api/dashboards/uid/ixora-push" 2>/dev/null || echo '{}')
D03_PROVISIONED=$(echo "${D03_API}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('meta',{}).get('provisioned',False))" 2>/dev/null || echo "false")
D03_FOLDER=$(echo "${D03_API}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('meta',{}).get('folderTitle','MISSING'))" 2>/dev/null || echo "MISSING")

if [ "${D03_PROVISIONED}" = "True" ] && [ "${D03_FOLDER}" = "Business" ]; then
  pass "ixora-push provisioned=true in Business folder"
elif [ "${D03_PROVISIONED}" = "True" ]; then
  fail "ixora-push provisioned but folder='${D03_FOLDER}' (expected Business)"
else
  fail "ixora-push not found or not provisioned (check Grafana container + volume)"
fi

# ── 52. D-03 datasource UID references ────────────────────────

echo ""
echo "52. D-03 datasource UID references (ixora-prometheus, no name-only)"

if [ -f "${D03_PATH}" ]; then
  D03_DS_CHECK=$(python3 -c "
import json, sys

with open('${D03_PATH}') as f:
    d = json.load(f)

bad = []
has_prom = False

def check_ds(obj, path):
    global has_prom
    if isinstance(obj, dict):
        if 'datasource' in obj and isinstance(obj['datasource'], dict):
            ds = obj['datasource']
            if 'uid' not in ds and ds.get('type') not in ('grafana',):
                bad.append(f'missing uid at {path}')
            if ds.get('uid','') == 'ixora-prometheus':
                has_prom = True
        for k, v in obj.items():
            check_ds(v, f'{path}.{k}')
    elif isinstance(obj, list):
        for i, item in enumerate(obj):
            check_ds(item, f'{path}[{i}]')

check_ds(d, 'root')

if bad:
    print('FAIL: datasource objects missing uid: ' + ' | '.join(bad[:5]))
elif not has_prom:
    print('FAIL: ixora-prometheus not referenced in D-03')
else:
    print('PASS: all datasource references use UID, ixora-prometheus present')
" 2>/dev/null || echo "FAIL: python3 datasource check failed")

  if echo "${D03_DS_CHECK}" | grep -q "^PASS:"; then
    pass "${D03_DS_CHECK#PASS: }"
  else
    fail "${D03_DS_CHECK#FAIL: }"
  fi
else
  fail "D-03 datasource check skipped — JSON file missing"
fi

# ── 53. D-03 contains dashboard-level navigation links ────────

echo ""
echo "53. D-03 contains navigation links to all 6 peer dashboards"

if [ -f "${D03_PATH}" ]; then
  D03_LINKS=$(python3 -c "
import json, sys

with open('${D03_PATH}') as f:
    d = json.load(f)

EXPECTED = [
    '/d/ixora-platform',
    '/d/ixora-smart-home',
    '/d/ixora-queue',
    '/d/ixora-http',
    '/d/ixora-scheduler',
    '/d/ixora-collector',
]

actual_urls = [l.get('url','') for l in d.get('links', []) if isinstance(l, dict)]
missing = [u for u in EXPECTED if u not in actual_urls]

if missing:
    print(f'FAIL: D-03 missing navigation links: {missing}')
else:
    print(f'PASS: D-03 contains all 6 peer navigation links')
" 2>/dev/null || echo "FAIL: python3 link check failed")

  if echo "${D03_LINKS}" | grep -q "^PASS:"; then
    pass "${D03_LINKS#PASS: }"
  else
    fail "${D03_LINKS#FAIL: }"
  fi
else
  fail "D-03 navigation link check skipped — JSON file missing"
fi

# ── 54. D-03 variables include $environment ───────────────────

echo ""
echo "54. D-03 dashboard variables include \$environment"

if [ -f "${D03_PATH}" ]; then
  D03_VARS=$(python3 -c "
import json, sys

with open('${D03_PATH}') as f:
    d = json.load(f)

var_names = [v.get('name','') for v in d.get('templating', {}).get('list', [])]

if 'environment' not in var_names:
    print(f'FAIL: \$environment variable missing from D-03 (found: {var_names})')
else:
    print(f'PASS: D-03 variables include \$environment (all vars: {var_names})')
" 2>/dev/null || echo "FAIL: python3 variable check failed")

  if echo "${D03_VARS}" | grep -q "^PASS:"; then
    pass "${D03_VARS#PASS: }"
  else
    fail "${D03_VARS#FAIL: }"
  fi
else
  fail "D-03 variable check skipped — JSON file missing"
fi

# ── 55. D-03 every non-row panel has a description ────────────

echo ""
echo "55. D-03 every non-row panel contains a description"

if [ -f "${D03_PATH}" ]; then
  D03_DESC=$(python3 -c "
import json, sys

with open('${D03_PATH}') as f:
    d = json.load(f)

missing = []
for p in d.get('panels', []):
    if p.get('type') == 'row':
        continue
    desc = p.get('description', '').strip()
    if not desc:
        missing.append(f'id={p.get(\"id\",\"?\")} title=\"{p.get(\"title\",\"\")}\"')

if missing:
    print(f'FAIL: panels missing description: ' + ' | '.join(missing))
else:
    count = sum(1 for p in d.get('panels',[]) if p.get('type') != 'row')
    print(f'PASS: all {count} non-row panels have a description')
" 2>/dev/null || echo "FAIL: python3 description check failed")

  if echo "${D03_DESC}" | grep -q "^PASS:"; then
    pass "${D03_DESC#PASS: }"
  else
    fail "${D03_DESC#FAIL: }"
  fi
else
  fail "D-03 description check skipped — JSON file missing"
fi

# ── 56. D-03 no duplicate panel IDs ──────────────────────────

echo ""
echo "56. D-03 no duplicate panel IDs"

if [ -f "${D03_PATH}" ]; then
  D03_DEDUP=$(python3 -c "
import json, sys

with open('${D03_PATH}') as f:
    d = json.load(f)

ids = [p.get('id') for p in d.get('panels', []) if 'id' in p]
seen = {}
for pid in ids:
    seen[pid] = seen.get(pid, 0) + 1
dupes = [pid for pid, c in seen.items() if c > 1]

if dupes:
    print(f'FAIL: duplicate panel IDs in D-03: {dupes}')
else:
    print(f'PASS: {len(ids)} panel IDs — all unique')
" 2>/dev/null || echo "FAIL: python3 duplicate check failed")

  if echo "${D03_DEDUP}" | grep -q "^PASS:"; then
    pass "${D03_DEDUP#PASS: }"
  else
    fail "${D03_DEDUP#FAIL: }"
  fi
else
  fail "D-03 duplicate ID check skipped — JSON file missing"
fi

# ── 57. D-03 panel IDs follow reserved ranges ─────────────────
# Row panels: 1–99
# Content panels: 100–599

echo ""
echo "57. D-03 panel IDs follow reserved ranges (rows 1–99, content 100–599)"

if [ -f "${D03_PATH}" ]; then
  D03_RANGES=$(python3 -c "
import json, sys

with open('${D03_PATH}') as f:
    d = json.load(f)

bad = []
for p in d.get('panels', []):
    pid = p.get('id')
    ptype = p.get('type', '')
    if pid is None:
        bad.append(f'panel missing id (type={ptype})')
        continue
    if ptype == 'row':
        if not (1 <= pid <= 99):
            bad.append(f'row panel id={pid} (expected 1–99)')
    else:
        if not (100 <= pid <= 599):
            bad.append(f'content panel id={pid} (expected 100–599)')

if bad:
    print('FAIL: panel ID range violations: ' + ' | '.join(bad))
else:
    total = len(d.get('panels', []))
    print(f'PASS: all {total} panels have IDs within reserved ranges (rows 1–99, content 100–599)')
" 2>/dev/null || echo "FAIL: python3 range check failed")

  if echo "${D03_RANGES}" | grep -q "^PASS:"; then
    pass "${D03_RANGES#PASS: }"
  else
    fail "${D03_RANGES#FAIL: }"
  fi
else
  fail "D-03 range check skipped — JSON file missing"
fi

# ── 58. Alerting provisioning directory exists ───────────────

echo ""
echo "58. Alerting provisioning directory exists (provisioning/alerting/)"

ALERTING_DIR="${PROVISIONING_DIR}/alerting"

if [ -d "${ALERTING_DIR}" ]; then
  pass "provisioning/alerting/ directory exists"
else
  fail "provisioning/alerting/ directory missing — run: mkdir -p ${ALERTING_DIR}"
fi

# ── 59. Contact points directory exists ──────────────────────

echo ""
echo "59. Contact points provisioning directory exists"

CONTACT_POINTS_DIR="${PROVISIONING_DIR}/contact-points"

if [ -d "${CONTACT_POINTS_DIR}" ]; then
  pass "provisioning/contact-points/ directory exists"
else
  fail "provisioning/contact-points/ directory missing — run: mkdir -p ${CONTACT_POINTS_DIR}"
fi

# ── 60. Notification policies directory exists ───────────────

echo ""
echo "60. Notification policies provisioning directory exists"

POLICIES_DIR="${PROVISIONING_DIR}/notification-policies"

if [ -d "${POLICIES_DIR}" ]; then
  pass "provisioning/notification-policies/ directory exists"
else
  fail "provisioning/notification-policies/ directory missing — run: mkdir -p ${POLICIES_DIR}"
fi

# ── 61. Mute timings directory exists ────────────────────────

echo ""
echo "61. Mute timings provisioning directory exists"

MUTE_DIR="${PROVISIONING_DIR}/mute-timings"

if [ -d "${MUTE_DIR}" ]; then
  pass "provisioning/mute-timings/ directory exists"
else
  fail "provisioning/mute-timings/ directory missing — run: mkdir -p ${MUTE_DIR}"
fi

# ── 62. Templates directory exists ───────────────────────────

echo ""
echo "62. Templates provisioning directory exists"

TEMPLATES_DIR="${PROVISIONING_DIR}/templates"

if [ -d "${TEMPLATES_DIR}" ]; then
  pass "provisioning/templates/ directory exists"
else
  fail "provisioning/templates/ directory missing — run: mkdir -p ${TEMPLATES_DIR}"
fi

# ── 63. Alerting philosophy document exists ──────────────────

echo ""
echo "63. Alerting philosophy document exists (docs/architecture/alerting-philosophy.md)"

SCRIPT_DIR_PARENT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
DOCS_DIR="${SCRIPT_DIR_PARENT}/docs"
ALERTING_PHIL="${DOCS_DIR}/architecture/alerting-philosophy.md"

if [ -f "${ALERTING_PHIL}" ]; then
  pass "alerting-philosophy.md found"
else
  fail "alerting-philosophy.md not found at ${ALERTING_PHIL}"
fi

# ── 64. Alerting foundation specification exists ─────────────

echo ""
echo "64. Alerting foundation specification exists (alerting-foundation.md)"

ALERTING_SPEC="${DOCS_DIR}/specs/observability-foundation/mvp/alerting-foundation.md"

if [ -f "${ALERTING_SPEC}" ]; then
  pass "alerting-foundation.md found"
else
  fail "alerting-foundation.md not found at ${ALERTING_SPEC}"
fi

# ── 65. contact-points.yaml is valid YAML ────────────────────

echo ""
echo "65. provisioning/alerting/contact-points.yaml is valid YAML"

# Phase 9 moved the real file into provisioning/alerting/ — see check 99
# and alerting-strategy.md §2.1 (Grafana never reads the sibling
# contact-points/ directory checked in check 59).
CONTACT_YAML="${ALERTING_DIR}/contact-points.yaml"

if [ -f "${CONTACT_YAML}" ]; then
  YAML_CHECK=$(python3 -c "
import yaml, sys
try:
    data = yaml.safe_load(open('${CONTACT_YAML}'))
    if data is None:
        print('FAIL: contact-points.yaml is empty')
    elif 'contactPoints' not in data and 'apiVersion' not in data:
        print('FAIL: contact-points.yaml missing expected keys')
    else:
        print('PASS: contact-points.yaml is valid YAML')
except Exception as e:
    print(f'FAIL: contact-points.yaml parse error: {e}')
" 2>/dev/null || echo "FAIL: python3 yaml check failed")

  if echo "${YAML_CHECK}" | grep -q "^PASS:"; then
    pass "${YAML_CHECK#PASS: }"
  else
    fail "${YAML_CHECK#FAIL: }"
  fi
else
  fail "provisioning/alerting/contact-points.yaml not found"
fi

# ── 66. policies.yaml is valid YAML ──────────────────────────

echo ""
echo "66. provisioning/alerting/notification-policies.yaml is valid YAML"

# Phase 9 moved the real file into provisioning/alerting/ and renamed it
# notification-policies.yaml — see check 99 and alerting-strategy.md §2.1.
POLICIES_YAML="${ALERTING_DIR}/notification-policies.yaml"

if [ -f "${POLICIES_YAML}" ]; then
  YAML_CHECK=$(python3 -c "
import yaml, sys
try:
    data = yaml.safe_load(open('${POLICIES_YAML}'))
    if data is None:
        print('FAIL: policies.yaml is empty')
    else:
        print('PASS: policies.yaml is valid YAML')
except Exception as e:
    print(f'FAIL: policies.yaml parse error: {e}')
" 2>/dev/null || echo "FAIL: python3 yaml check failed")

  if echo "${YAML_CHECK}" | grep -q "^PASS:"; then
    pass "${YAML_CHECK#PASS: }"
  else
    fail "${YAML_CHECK#FAIL: }"
  fi
else
  fail "provisioning/alerting/notification-policies.yaml not found"
fi

# ── 67. mute-timings.yaml is valid YAML ──────────────────────

echo ""
echo "67. provisioning/alerting/mute-timings.yaml is valid YAML"

# Phase 9 moved the real file into provisioning/alerting/ — see check 99
# and alerting-strategy.md §2.1.
MUTE_YAML="${ALERTING_DIR}/mute-timings.yaml"

if [ -f "${MUTE_YAML}" ]; then
  YAML_CHECK=$(python3 -c "
import yaml, sys
try:
    data = yaml.safe_load(open('${MUTE_YAML}'))
    if data is None:
        print('FAIL: mute-timings.yaml is empty')
    else:
        print('PASS: mute-timings.yaml is valid YAML')
except Exception as e:
    print(f'FAIL: mute-timings.yaml parse error: {e}')
" 2>/dev/null || echo "FAIL: python3 yaml check failed")

  if echo "${YAML_CHECK}" | grep -q "^PASS:"; then
    pass "${YAML_CHECK#PASS: }"
  else
    fail "${YAML_CHECK#FAIL: }"
  fi
else
  fail "provisioning/alerting/mute-timings.yaml not found"
fi

# ── 68. Recording rules directory exists ─────────────────────

echo ""
echo "68. Recording rules directory exists (prometheus/rules/recording/)"

COLLECTOR_DIR="$(dirname "${SCRIPT_DIR}")"
RECORDING_RULES_DIR="${COLLECTOR_DIR}/prometheus/rules/recording"

if [ -d "${RECORDING_RULES_DIR}" ]; then
  pass "prometheus/rules/recording/ directory exists"
else
  fail "prometheus/rules/recording/ directory missing — run: mkdir -p ${RECORDING_RULES_DIR}"
fi

# ── 69. application.rules.yml is valid YAML ──────────────────

echo ""
echo "69. application.rules.yml exists and is valid YAML"

APP_RULES="${RECORDING_RULES_DIR}/application.rules.yml"

if [ -f "${APP_RULES}" ]; then
  YAML_CHECK=$(python3 -c "
import yaml
try:
    data = yaml.safe_load(open('${APP_RULES}'))
    if data is None or 'groups' not in data:
        print('FAIL: application.rules.yml missing groups key')
    else:
        print('PASS: application.rules.yml is valid YAML with groups')
except Exception as e:
    print(f'FAIL: application.rules.yml parse error: {e}')
" 2>/dev/null || echo "FAIL: python3 yaml check failed")

  if echo "${YAML_CHECK}" | grep -q "^PASS:"; then
    pass "${YAML_CHECK#PASS: }"
  else
    fail "${YAML_CHECK#FAIL: }"
  fi
else
  fail "application.rules.yml not found"
fi

# ── 70. business.rules.yml is valid YAML ─────────────────────

echo ""
echo "70. business.rules.yml exists and is valid YAML"

BIZ_RULES="${RECORDING_RULES_DIR}/business.rules.yml"

if [ -f "${BIZ_RULES}" ]; then
  YAML_CHECK=$(python3 -c "
import yaml
try:
    data = yaml.safe_load(open('${BIZ_RULES}'))
    if data is None or 'groups' not in data:
        print('FAIL: business.rules.yml missing groups key')
    else:
        print('PASS: business.rules.yml is valid YAML with groups')
except Exception as e:
    print(f'FAIL: business.rules.yml parse error: {e}')
" 2>/dev/null || echo "FAIL: python3 yaml check failed")

  if echo "${YAML_CHECK}" | grep -q "^PASS:"; then
    pass "${YAML_CHECK#PASS: }"
  else
    fail "${YAML_CHECK#FAIL: }"
  fi
else
  fail "business.rules.yml not found"
fi

# ── 71. infrastructure.rules.yml is valid YAML ───────────────

echo ""
echo "71. infrastructure.rules.yml exists and is valid YAML"

INFRA_RULES="${RECORDING_RULES_DIR}/infrastructure.rules.yml"

if [ -f "${INFRA_RULES}" ]; then
  YAML_CHECK=$(python3 -c "
import yaml
try:
    data = yaml.safe_load(open('${INFRA_RULES}'))
    if data is None or 'groups' not in data:
        print('FAIL: infrastructure.rules.yml missing groups key')
    else:
        print('PASS: infrastructure.rules.yml is valid YAML with groups')
except Exception as e:
    print(f'FAIL: infrastructure.rules.yml parse error: {e}')
" 2>/dev/null || echo "FAIL: python3 yaml check failed")

  if echo "${YAML_CHECK}" | grep -q "^PASS:"; then
    pass "${YAML_CHECK#PASS: }"
  else
    fail "${YAML_CHECK#FAIL: }"
  fi
else
  fail "infrastructure.rules.yml not found"
fi

# ── 72. slo.rules.yml is valid YAML ──────────────────────────

echo ""
echo "72. slo.rules.yml exists and is valid YAML"

SLO_RULES="${RECORDING_RULES_DIR}/slo.rules.yml"

if [ -f "${SLO_RULES}" ]; then
  YAML_CHECK=$(python3 -c "
import yaml
try:
    data = yaml.safe_load(open('${SLO_RULES}'))
    if data is None or 'groups' not in data:
        print('FAIL: slo.rules.yml missing groups key')
    else:
        print('PASS: slo.rules.yml is valid YAML with groups')
except Exception as e:
    print(f'FAIL: slo.rules.yml parse error: {e}')
" 2>/dev/null || echo "FAIL: python3 yaml check failed")

  if echo "${YAML_CHECK}" | grep -q "^PASS:"; then
    pass "${YAML_CHECK#PASS: }"
  else
    fail "${YAML_CHECK#FAIL: }"
  fi
else
  fail "slo.rules.yml not found"
fi

# ── 63/73 helpers: docs paths (reuse if not yet set) ─────────

SCRIPT_DIR_PARENT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
DOCS_DIR="${SCRIPT_DIR_PARENT}/docs"

# ── 73. Recording rules philosophy document exists ───────────

echo ""
echo "73. Recording rules philosophy document exists (recording-rules-philosophy.md)"

RR_PHIL="${DOCS_DIR}/architecture/recording-rules-philosophy.md"

if [ -f "${RR_PHIL}" ]; then
  pass "recording-rules-philosophy.md found"
else
  fail "recording-rules-philosophy.md not found at ${RR_PHIL}"
fi

# ── 74. SLO philosophy document exists ───────────────────────

echo ""
echo "74. SLO philosophy document exists (slo-philosophy.md)"

SLO_PHIL="${DOCS_DIR}/architecture/slo-philosophy.md"

if [ -f "${SLO_PHIL}" ]; then
  pass "slo-philosophy.md found"
else
  fail "slo-philosophy.md not found at ${SLO_PHIL}"
fi

# ── 75. Recording rules foundation specification exists ────

echo ""
echo "75. Recording rules foundation specification exists (recording-rules-foundation.md)"

RR_SPEC="${DOCS_DIR}/specs/observability-foundation/mvp/recording-rules-foundation.md"

if [ -f "${RR_SPEC}" ]; then
  pass "recording-rules-foundation.md found"
else
  fail "recording-rules-foundation.md not found at ${RR_SPEC}"
fi

# ── 76. Catalog documented (REC-001) ─────────────────────────

echo ""
echo "76. Recording rule catalog documented (REC-001)"

if [ -f "${RR_SPEC}" ] && grep -q "REC-001" "${RR_SPEC}"; then
  pass "REC-001 catalog entry found in recording-rules-foundation.md"
else
  fail "REC-001 not found in recording-rules-foundation.md"
fi

# ── 77. SLI definitions documented (SLI-001) ─────────────────

echo ""
echo "77. SLI definitions documented (SLI-001)"

if [ -f "${RR_SPEC}" ] && grep -q "SLI-001" "${RR_SPEC}"; then
  pass "SLI-001 definition found in recording-rules-foundation.md"
else
  fail "SLI-001 not found in recording-rules-foundation.md"
fi

# ── 78. Naming convention documented ─────────────────────────

echo ""
echo "78. Naming convention documented (ixora:http:error_rate:5m)"

if [ -f "${RR_SPEC}" ] && grep -q "ixora:http:error_rate:5m" "${RR_SPEC}"; then
  pass "ixora:http:error_rate:5m naming convention documented"
else
  fail "ixora:http:error_rate:5m not found in recording-rules-foundation.md"
fi

# ── Phase 8.8.6: Observability Infrastructure Hardening ─────

HARDENING_DIR="${DOCS_DIR}/specs/observability-foundation/mvp"

# ── 79. observability-hardening.md exists ───────────────────

echo ""
echo "79. Observability hardening index document exists (observability-hardening.md)"

HARDENING_DOC="${HARDENING_DIR}/observability-hardening.md"

if [ -f "${HARDENING_DOC}" ]; then
  pass "observability-hardening.md found"
else
  fail "observability-hardening.md not found at ${HARDENING_DOC}"
fi

# ── 80. deployment-strategy.md exists ───────────────────────

echo ""
echo "80. Deployment strategy document exists (deployment-strategy.md)"

DEPLOY_DOC="${HARDENING_DIR}/deployment-strategy.md"

if [ -f "${DEPLOY_DOC}" ]; then
  pass "deployment-strategy.md found"
else
  fail "deployment-strategy.md not found at ${DEPLOY_DOC}"
fi

# ── 81. backup-strategy.md exists ───────────────────────────

echo ""
echo "81. Backup strategy document exists (backup-strategy.md)"

BACKUP_DOC="${HARDENING_DIR}/backup-strategy.md"

if [ -f "${BACKUP_DOC}" ]; then
  pass "backup-strategy.md found"
else
  fail "backup-strategy.md not found at ${BACKUP_DOC}"
fi

# ── 82. storage-strategy.md exists ──────────────────────────

echo ""
echo "82. Storage strategy document exists (storage-strategy.md)"

STORAGE_DOC="${HARDENING_DIR}/storage-strategy.md"

if [ -f "${STORAGE_DOC}" ]; then
  pass "storage-strategy.md found"
else
  fail "storage-strategy.md not found at ${STORAGE_DOC}"
fi

# ── 83. future-cicd.md exists ───────────────────────────────

echo ""
echo "83. Future CI/CD architecture document exists (future-cicd.md)"

CICD_DOC="${HARDENING_DIR}/future-cicd.md"

if [ -f "${CICD_DOC}" ]; then
  pass "future-cicd.md found"
else
  fail "future-cicd.md not found at ${CICD_DOC}"
fi

# ── 84. cloud-init-review.md exists ─────────────────────────

echo ""
echo "84. Cloud-init review document exists (cloud-init-review.md)"

CLOUDINIT_DOC="${HARDENING_DIR}/cloud-init-review.md"

if [ -f "${CLOUDINIT_DOC}" ]; then
  pass "cloud-init-review.md found"
else
  fail "cloud-init-review.md not found at ${CLOUDINIT_DOC}"
fi

# ── 85. app-platform-otel-integration.md exists ─────────────

echo ""
echo "85. App Platform OTEL integration document exists (app-platform-otel-integration.md)"

APP_OTEL_DOC="${HARDENING_DIR}/app-platform-otel-integration.md"

if [ -f "${APP_OTEL_DOC}" ]; then
  pass "app-platform-otel-integration.md found"
else
  fail "app-platform-otel-integration.md not found at ${APP_OTEL_DOC}"
fi

# ── 86. Release deployment strategy documented ──────────────

echo ""
echo "86. Release deployment strategy documented (release-YYYY.MM.DD pattern)"

if [ -f "${DEPLOY_DOC}" ] && grep -q "release-2026" "${DEPLOY_DOC}"; then
  pass "Release tag deployment pattern documented in deployment-strategy.md"
else
  fail "Release deployment pattern not found in deployment-strategy.md"
fi

# ── 87. Backup architecture covers all backends ─────────────

echo ""
echo "87. Backup architecture covers Prometheus, Loki, Tempo, Grafana"

if [ -f "${BACKUP_DOC}" ] && grep -q "Prometheus" "${BACKUP_DOC}" && grep -q "Loki" "${BACKUP_DOC}" && grep -q "Tempo" "${BACKUP_DOC}" && grep -q "Grafana" "${BACKUP_DOC}"; then
  pass "Backup strategy documents Prometheus, Loki, Tempo, and Grafana"
else
  fail "Backup strategy missing one or more backend sections"
fi

# ── 88. Hardening cross-references provisioning doc ─────────

echo ""
echo "88. Hardening doc cross-references provisioning doc"

PROV_DOC="${HARDENING_DIR}/observability-infrastructure-provisioning.md"

if [ -f "${HARDENING_DOC}" ] && grep -q "observability-infrastructure-provisioning.md" "${HARDENING_DOC}"; then
  pass "observability-hardening.md references provisioning doc"
else
  fail "observability-hardening.md missing cross-reference to provisioning doc"
fi

# ── 89. Reserved IP variable documented ───────────────────────

echo ""
echo "89. Reserved IP OpenTofu variable documented (observability_use_reserved_ip)"

VARS_TF="${SCRIPT_DIR_PARENT}/opentofu/staging/variables.tf"

if [ -f "${VARS_TF}" ] && grep -q "observability_use_reserved_ip" "${VARS_TF}"; then
  pass "observability_use_reserved_ip variable found in variables.tf"
else
  fail "observability_use_reserved_ip not found in opentofu/staging/variables.tf"
fi

# ── 90. Single deploy script referenced ───────────────────────

echo ""
echo "90. Deployment strategy references deploy-observability.sh (no duplicate deploy path)"

DEPLOY_SCRIPT="${SCRIPT_DIR_PARENT}/scripts/deploy-observability.sh"
DEPLOY_SCRIPT_REFS=0

if [ -f "${DEPLOY_DOC}" ] && grep -c "deploy-observability.sh" "${DEPLOY_DOC}" >/dev/null 2>&1; then
  DEPLOY_SCRIPT_REFS=$(grep -c "deploy-observability.sh" "${DEPLOY_DOC}" || echo 0)
fi

if [ -f "${DEPLOY_SCRIPT}" ] && [ "${DEPLOY_SCRIPT_REFS}" -ge 1 ]; then
  pass "deploy-observability.sh exists and is referenced in deployment-strategy.md"
else
  fail "deploy-observability.sh missing or not referenced in deployment-strategy.md"
fi

# ── Phase 8.9 SLO implementation checks (91–98) ───────────────

echo ""
echo "91. D-08 SLO dashboard JSON syntax"

D08_PATH="${PROVISIONING_DIR}/dashboards/overview/d08-slo-error-budget.json"
check_json_syntax "D-08 SLO & Error Budget" "${D08_PATH}"

echo ""
echo "92. D-08 dashboard UID (ixora-slo)"

check_dashboard_uid_in_file "D-08 SLO JSON file" "${D08_PATH}" "ixora-slo"

echo ""
echo "93. slo.alerts.yml exists and is valid YAML"

SLO_ALERTS="${COLLECTOR_DIR}/prometheus/rules/alerting/slo.alerts.yml"
if [ -f "${SLO_ALERTS}" ]; then
  YAML_CHECK=$(python3 -c "
import yaml
try:
    data = yaml.safe_load(open('${SLO_ALERTS}'))
    if data is None or 'groups' not in data:
        print('FAIL: slo.alerts.yml missing groups key')
    else:
        print('PASS: slo.alerts.yml is valid YAML with groups')
except Exception as e:
    print(f'FAIL: slo.alerts.yml parse error: {e}')
" 2>/dev/null || echo "FAIL: python3 yaml check failed")
  if echo "${YAML_CHECK}" | grep -q "^PASS:"; then
    pass "${YAML_CHECK#PASS: }"
  else
    fail "${YAML_CHECK#FAIL: }"
  fi
else
  fail "slo.alerts.yml not found at ${SLO_ALERTS}"
fi

echo ""
echo "94. Prometheus rule_files active in prometheus.yml"

PROM_YML="${COLLECTOR_DIR}/prometheus/prometheus.yml"
if [ -f "${PROM_YML}" ] && grep -q "^rule_files:" "${PROM_YML}" && grep -q "recording/\*.rules.yml" "${PROM_YML}"; then
  pass "prometheus.yml rule_files includes recording and alerting paths"
else
  fail "prometheus.yml rule_files not active or missing recording path"
fi

echo ""
echo "95. promtool check rules (recording + alerting)"

PROMTOOL_BIN=""
if command -v promtool >/dev/null 2>&1; then
  PROMTOOL_BIN="promtool"
else
  PROMTOOL_BIN="docker run --rm -v ${COLLECTOR_DIR}/prometheus:/etc/prometheus:ro prom/prometheus:v2.54.1 promtool"
fi

PROMTOOL_OK=1
if command -v promtool >/dev/null 2>&1; then
  for rules_file in "${RECORDING_RULES_DIR}"/*.rules.yml "${COLLECTOR_DIR}/prometheus/rules/alerting"/*.yml; do
    [ -f "${rules_file}" ] || continue
    if promtool check rules "${rules_file}" >/dev/null 2>&1; then
      :
    else
      PROMTOOL_OK=0
      fail "promtool check rules failed: $(basename "${rules_file}")"
    fi
  done
else
  for rules_file in "${RECORDING_RULES_DIR}"/*.rules.yml "${COLLECTOR_DIR}/prometheus/rules/alerting"/*.yml; do
    [ -f "${rules_file}" ] || continue
    rel="${rules_file#${COLLECTOR_DIR}/prometheus/}"
    if docker run --rm --entrypoint promtool -v "${COLLECTOR_DIR}/prometheus:/etc/prometheus:ro" prom/prometheus:v2.54.1 \
      check rules "/etc/prometheus/${rel}" >/dev/null 2>&1; then
      :
    else
      PROMTOOL_OK=0
      fail "promtool check rules failed: $(basename "${rules_file}")"
    fi
  done
fi
if [ "${PROMTOOL_OK}" -eq 1 ]; then
  pass "promtool check rules passed for all recording and alerting files"
fi

echo ""
echo "96. SLO runbook exists (docs/runbooks/slo-error-budget.md)"

SLO_RUNBOOK="${DOCS_DIR}/runbooks/slo-error-budget.md"
if [ -f "${SLO_RUNBOOK}" ]; then
  pass "slo-error-budget.md runbook found"
else
  fail "slo-error-budget.md not found at ${SLO_RUNBOOK}"
fi

echo ""
echo "97. SLO mathematical fixture tests"

MATH_TEST="${COLLECTOR_DIR}/scripts/test-slo-math.py"
if [ -f "${MATH_TEST}" ]; then
  if python3 "${MATH_TEST}" >/dev/null 2>&1; then
    pass "test-slo-math.py — all fixture tests passed"
  else
    fail "test-slo-math.py failed — run: python3 ${MATH_TEST}"
  fi
else
  fail "test-slo-math.py not found at ${MATH_TEST}"
fi

echo ""
echo "98. docker-compose mounts prometheus rules directory"

COMPOSE_FILE="${COLLECTOR_DIR}/docker-compose.yml"
if [ -f "${COMPOSE_FILE}" ] && grep -q "prometheus/rules" "${COMPOSE_FILE}"; then
  pass "docker-compose.yml mounts ./prometheus/rules"
else
  fail "docker-compose.yml missing prometheus/rules volume mount"
fi

# ── 99. Alerting resource files live under provisioning/alerting/ ─
#
# Regression guard for a real Phase 9 bug: Grafana's file-provisioning
# only scans provisioning/alerting/ — files left in the sibling
# contact-points/, notification-policies/, mute-timings/, templates/
# directories (as alerting-foundation.md §3.2 originally, incorrectly,
# documented) are silently never loaded. See alerting-strategy.md §2.1.

echo ""
echo "99. Contact points / policies / mute timings / templates live under provisioning/alerting/"

MISSING_IN_ALERTING=""
for f in contact-points.yaml notification-policies.yaml mute-timings.yaml templates.yaml; do
  if [ ! -f "${ALERTING_DIR}/${f}" ]; then
    MISSING_IN_ALERTING="${MISSING_IN_ALERTING} ${f}"
  fi
done

STRAY_IN_SIBLINGS=""
for d in contact-points notification-policies mute-timings templates; do
  if find "${PROVISIONING_DIR}/${d}" -maxdepth 1 -name '*.yaml' 2>/dev/null | grep -q .; then
    STRAY_IN_SIBLINGS="${STRAY_IN_SIBLINGS} ${d}/"
  fi
done

if [ -z "${MISSING_IN_ALERTING}" ] && [ -z "${STRAY_IN_SIBLINGS}" ]; then
  pass "contact-points.yaml, notification-policies.yaml, mute-timings.yaml, templates.yaml all present under provisioning/alerting/, none stray in sibling directories"
else
  [ -n "${MISSING_IN_ALERTING}" ] && fail "missing under provisioning/alerting/:${MISSING_IN_ALERTING}"
  [ -n "${STRAY_IN_SIBLINGS}" ] && fail "stray .yaml file(s) in sibling directories (never loaded by Grafana):${STRAY_IN_SIBLINGS}"
fi

# ── 100. Real (non-placeholder) email contact point present ──────

echo ""
echo "100. contact-points.yaml has a real receiver (not the empty-addresses placeholder)"

CONTACT_YAML="${ALERTING_DIR}/contact-points.yaml"

if [ -f "${CONTACT_YAML}" ]; then
  if grep -q 'name: ixora-email-critical' "${CONTACT_YAML}" && ! grep -q 'addresses: ""' "${CONTACT_YAML}"; then
    pass "ixora-email-critical receiver present with a non-empty addresses field"
  else
    fail "contact-points.yaml still looks like the Phase 8.8 placeholder (no ixora-email-critical receiver, or addresses is empty)"
  fi
else
  fail "provisioning/alerting/contact-points.yaml not found"
fi

# ── 101. All 7 Phase 9 alert rule files present ───────────────────

echo ""
echo "101. All 7 Phase 9 alert rule files present under provisioning/alerting/"

MISSING_RULE_FILES=""
for f in infrastructure-collector.yaml application-http.yaml application-queue.yaml \
         application-scheduler.yaml application-push.yaml business-smart-home.yaml; do
  if [ ! -f "${ALERTING_DIR}/${f}" ]; then
    MISSING_RULE_FILES="${MISSING_RULE_FILES} ${f}"
  fi
done

if [ -z "${MISSING_RULE_FILES}" ]; then
  pass "all 6 Phase 9 alert rule group files present (7 rules total — application-http.yaml holds 2)"
else
  fail "missing alert rule file(s):${MISSING_RULE_FILES}"
fi

# ── 102. All 7 Phase 9 runbooks present ───────────────────────────

echo ""
echo "102. All 7 Phase 9 runbooks present under docs/runbooks/"

RUNBOOKS_DIR="${DOCS_DIR}/runbooks"
MISSING_RUNBOOKS=""
for f in infrastructure-collector-down.md application-http-error-rate.md \
         application-http-high-latency.md application-queue-failure-rate.md \
         application-scheduler-missed.md application-push-failure.md \
         business-smart-home-failure.md; do
  if [ ! -f "${RUNBOOKS_DIR}/${f}" ]; then
    MISSING_RUNBOOKS="${MISSING_RUNBOOKS} ${f}"
  fi
done

if [ -z "${MISSING_RUNBOOKS}" ]; then
  pass "all 7 Phase 9 runbooks present"
else
  fail "missing runbook(s):${MISSING_RUNBOOKS}"
fi

# ── 103. No alert rule references a known-nonexistent metric ─────
#
# Regression guard for the three metric/label names found wrong in
# Phase 9 testing against back_vibes/app/Telemetry (alerting-strategy.md
# §3.1): http_status_code (no such label — real one is
# outcome="server_error"), ixora_scheduler_execution_total (real name is
# ixora_scheduler_event_total), and ixora_telemetry_export_failed_total
# (never instrumented — use the ixora:collector:export_failure_rate:5m
# recording rule instead).

echo ""
echo "103. No alert rule expr references a known-nonexistent metric/label"

# Comment lines legitimately mention the old (wrong) names as an
# explanation of the fix — strip comments per file before matching so
# only a real reference (e.g. inside `expr:`) trips this check.
STALE_REFS=""
for f in "${ALERTING_DIR}"/*.yaml; do
  if grep -vE '^\s*#' "$f" | grep -qE 'http_status_code|ixora_scheduler_execution_total|ixora_telemetry_export_failed_total'; then
    STALE_REFS="${STALE_REFS} ${f}"
  fi
done

if [ -z "${STALE_REFS}" ]; then
  pass "no alert rule references http_status_code, ixora_scheduler_execution_total, or ixora_telemetry_export_failed_total"
else
  fail "stale metric/label reference found in: ${STALE_REFS}"
fi

# ── 104. No annotation templates a static rule label ──────────────
#
# Regression guard for a real Phase 9 bug, confirmed against a genuinely
# firing alert (real OTLP data pushed through the actual Collector
# pipeline, not a synthetic test): Grafana evaluates annotation
# templates (`{{ $labels.X }}`) against the labels in the QUERY RESULT
# only. Every Phase 9 rule aggregates with `sum(...)` (or references a
# label-less recording rule), which strips all labels from the query
# result — so `{{ $labels.dashboard_uid }}` / `{{ $labels.runbook }}`
# rendered "[no value]" even though dashboard_uid/runbook ARE present as
# static labels on the rule (query-result labels and the rule's own
# static labels are different template contexts). Fixed by hardcoding
# the literal dashboard/runbook path in each rule's annotations, the
# same way summary/business_impact/expected_action already are.
# alerting-strategy.md §3.3 has the full writeup and the live Mailtrap
# proof (message timestamps matching the alert's Pending->Alerting
# transition).

echo ""
echo "104. No alert rule annotation templates \$labels.dashboard_uid or \$labels.runbook"

TEMPLATED_ANNOTATIONS=""
for f in "${ALERTING_DIR}"/*.yaml; do
  if grep -vE '^\s*#' "$f" | grep -qE '\{\{\s*\$labels\.(dashboard_uid|runbook)\s*\}\}'; then
    TEMPLATED_ANNOTATIONS="${TEMPLATED_ANNOTATIONS} ${f}"
  fi
done

if [ -z "${TEMPLATED_ANNOTATIONS}" ]; then
  pass "dashboard/runbook annotations are literal strings, not \$labels templates"
else
  fail "annotation still templates a static rule label (always renders [no value]) in: ${TEMPLATED_ANNOTATIONS}"
fi

# ── 105. DatasourceNoData route appears BEFORE severity routes ────
#
# Regression guard for KL-IR-6 (incident-response-policy.md §9):
# Alertmanager's `group_wait` only fires for a group's very first
# notification; subsequent members of an existing group wait for the
# next `group_interval` flush instead. DatasourceNoData synthetic
# alerts share the same severity/category/environment labels as real
# alert rules, keeping those groups permanently "warm" — so a real
# alert joining the group can wait up to one full group_interval
# (15m for warning, 5m for critical) beyond its configured group_wait.
#
# The fix routes every DatasourceNoData alert into its own group via
# a dedicated route that MUST appear before any severity-based route.
# This check enforces that ordering: the first non-comment "matchers:"
# block in notification-policies.yaml must reference DatasourceNoData,
# and a severity matcher must not appear before it.

echo ""
echo "105. DatasourceNoData isolation route is the first route in notification-policies.yaml"

POLICIES_YAML="${ALERTING_DIR}/notification-policies.yaml"

if [ -f "${POLICIES_YAML}" ]; then
  CHECK_105=$(python3 -c "
import yaml, sys

with open('${POLICIES_YAML}') as f:
    data = yaml.safe_load(f)

policies = data.get('policies', [])
if not policies:
    print('FAIL: no policies found')
    sys.exit()

routes = policies[0].get('routes', [])
if not routes:
    print('FAIL: no routes found in root policy')
    sys.exit()

first = routes[0]
matchers = first.get('matchers', [])
has_nodata = any('DatasourceNoData' in str(m) for m in matchers)
if not has_nodata:
    print('FAIL: first route does not match DatasourceNoData — real alerts may share a group with NoData noise and miss group_wait')
    sys.exit()

# Also verify no severity matcher appears before DatasourceNoData
for i, route in enumerate(routes):
    ms = route.get('matchers', [])
    if any('severity' in str(m) for m in ms):
        if i == 0:
            print('FAIL: a severity-based route appears before the DatasourceNoData route')
            sys.exit()
        break

print('PASS: DatasourceNoData isolation route is first; severity routes follow')
" 2>/dev/null || echo "FAIL: python3 check failed")

  if echo "${CHECK_105}" | grep -q "^PASS:"; then
    pass "${CHECK_105#PASS: }"
  else
    fail "${CHECK_105#FAIL: }"
  fi
else
  fail "provisioning/alerting/notification-policies.yaml not found"
fi

# ── Summary ───────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────"
if [[ "${FAIL_COUNT}" -eq 0 ]]; then
  green "PASS: All ${PASS_COUNT} checks passed. Grafana foundation is ready."
  echo ""
else
  red "FAIL: ${FAIL_COUNT} check(s) failed, ${PASS_COUNT} passed."
  echo ""
  exit 1
fi
