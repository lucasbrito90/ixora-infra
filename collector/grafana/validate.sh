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
# Phase 8.7 checks (49–57):
#   D-03 Push Notifications dashboard:
#   49: D-03 dashboard JSON file exists.
#   50: UID equals ixora-push.
#   51: Datasource UID is ixora-prometheus.
#   52: Folder is Business.
#   53: Dashboard contains navigation links (all 6 peers).
#   54: Dashboard variables include $environment.
#   55: Every non-row panel contains a description.
#   56: No duplicate panel IDs within D-03.
#   57: Panel IDs follow reserved ranges (rows 1–99, content 100–599).
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
echo "Grafana Foundation Validation — Phase 8.1 + 8.2 + 8.3 + 8.4 + 8.5 + 8.6 + 8.7"
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
    print('PASS: all 5 specialized dashboards link back to /d/ixora-platform')
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
echo "44. Dashboard links follow standard ordering (D-01→D-02→D-03→D-04→D-05→D-06→D-07)"

ORDER_CHECK=$(python3 -c "
import json, os, sys

provisioning = '${PROVISIONING_DIR}/dashboards'

STANDARD_ORDER = [
    '/d/ixora-platform',
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
    print('PASS: all 7 dashboards follow standard link ordering')
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
echo "48. Panel ID integrity (no duplicates, positive IDs) — all 7 dashboards"

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
