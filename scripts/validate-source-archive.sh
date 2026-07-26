#!/usr/bin/env bash
# ============================================================
# validate-source-archive.sh
#
# Inspect a ZIP archive for forbidden paths and high-confidence
# secret patterns. Designed to be called after package-source-safe.sh.
#
# Usage:
#   ./scripts/validate-source-archive.sh <archive.zip>
#   ./scripts/validate-source-archive.sh <archive.zip> --keep-failed
#
# Options:
#   --keep-failed    Do not delete the archive on validation failure
#   --help           Show this help
#
# Exit codes:
#   0  Archive passed all checks (safe to share subject to the caveat below)
#   1  Forbidden path or high-confidence secret pattern detected
#
# IMPORTANT: A successful scan reduces risk but does not guarantee an
# archive contains no sensitive business data. Always review the file
# list before sharing externally.
# ============================================================

set -euo pipefail

ARCHIVE=""
KEEP_FAILED=0

# ── Argument parsing ──────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-failed) KEEP_FAILED=1; shift ;;
    --help|-h)
      grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*)
      printf 'ERROR: Unknown option: %s\n' "$1" >&2
      exit 1
      ;;
    *)
      if [[ -z "${ARCHIVE}" ]]; then
        ARCHIVE="$1"
        shift
      else
        printf 'ERROR: Unexpected argument: %s\n' "$1" >&2
        exit 1
      fi
      ;;
  esac
done

if [[ -z "${ARCHIVE}" ]]; then
  printf 'ERROR: No archive specified.\n' >&2
  printf 'Usage: %s <archive.zip> [--keep-failed]\n' "$0" >&2
  exit 1
fi

if [[ ! -f "${ARCHIVE}" ]]; then
  printf 'ERROR: File not found: %s\n' "${ARCHIVE}" >&2
  exit 1
fi

# ── Forbidden path patterns ───────────────────────────────────────────────
#
# Matched against each entry path inside the archive.
#
FORBIDDEN_PATH_PATTERNS=(
  '\.git/'
  '\.git$'
  'collector/\.env$'
  '^\.env$'
  '\.env\.'
  'terraform\.tfvars$'
  'terraform\.tfvars\.json$'
  '\.auto\.tfvars$'
  '\.auto\.tfvars\.json$'
  '\.tfstate$'
  '\.tfstate\.'
  '\.tfplan$'
  '/tfplan$'
  '/plan\.json$'
  '/plan.*\.json$'
  '/\.terraform/'
  'crash\.log$'
  '\.pem$'
  '(^|/)\.key$'
  '/id_rsa$'
  '/id_ed25519$'
  '/id_ecdsa$'
)

# ── High-confidence secret patterns ──────────────────────────────────────
#
# Used to scan text file CONTENTS. Each entry is: "RULE_NAME|REGEX"
# The regex must be ERE (grep -E).
#
# Placeholders are allowed and must NOT trigger a match:
#   CHANGE_ME, REPLACE_WITH_STRONG, <SECRET>, empty values
#
SECRET_PATTERNS=(
  "PRIVATE_KEY_HEADER|-----BEGIN (RSA |EC |OPENSSH |)PRIVATE KEY-----"
  "DO_PAT_TOKEN|dop_v1_[a-f0-9]{64}"
  "DO_OAUTH_TOKEN|DO00[a-f0-9]{60}"
  "AWS_SECRET_KEY|AWS_SECRET_ACCESS_KEY=[A-Za-z0-9/+]{40}"
  "FIREBASE_PRIVATE_KEY|FIREBASE_PRIVATE_KEY=.{20,}"
  "GF_ADMIN_PASSWORD_REAL|GF_ADMIN_PASSWORD=[^ \t\"'<]{8,}"
  "OTEL_BACKEND_KEY_REAL|OTEL_INGEST_API_KEY_BACKEND=[a-f0-9]{32,}"
  "OTEL_MOBILE_KEY_REAL|OTEL_INGEST_API_KEY_MOBILE=[a-f0-9]{32,}"
  "DATABASE_PASSWORD_REAL|DATABASE_PASSWORD=[^ \t\"'<]{8,}"
  "DB_PASSWORD_REAL|DB_PASSWORD=[^ \t\"'<]{8,}"
)

# Placeholder values that are explicitly safe and must not trigger detection
SAFE_PLACEHOLDERS=(
  "CHANGE_ME"
  "REPLACE_WITH_STRONG"
  "<SECRET>"
  "your_.*_here"
  "EXAMPLE"
  "example"
  "placeholder"
  "PLACEHOLDER"
  "\-dev$"
  "ixora-grafana"
  "strong-password"
  "openssl rand"
)

# ── Temp directory ────────────────────────────────────────────────────────

WORK_DIR="$(mktemp -d /tmp/ixora-validate-XXXXXX)"

# shellcheck disable=SC2329  # cleanup is invoked via trap, not directly
cleanup() {
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

# ── Step 1: List archive contents ─────────────────────────────────────────

printf '[INFO] Validating archive: %s\n' "${ARCHIVE}"

ENTRY_LIST="${WORK_DIR}/entries.txt"
unzip -Z1 "${ARCHIVE}" > "${ENTRY_LIST}" 2>/dev/null || {
  printf 'ERROR: Failed to list archive contents (corrupt or not a ZIP?)\n' >&2
  exit 1
}

TOTAL_ENTRIES="$(wc -l < "${ENTRY_LIST}")"
printf '[INFO] Archive entries: %d\n' "${TOTAL_ENTRIES}"

# ── Step 2: Check forbidden paths ─────────────────────────────────────────

FORBIDDEN_FOUND=0

while IFS= read -r entry; do
  # .example files are safe by design and must never be flagged
  if [[ "${entry}" == *.example ]]; then
    continue
  fi
  for pattern in "${FORBIDDEN_PATH_PATTERNS[@]}"; do
    if echo "${entry}" | grep -qE "${pattern}"; then
      printf '[FAIL] Forbidden path detected: %s  [rule: %s]\n' "${entry}" "${pattern}" >&2
      FORBIDDEN_FOUND=1
      break
    fi
  done
done < "${ENTRY_LIST}"

# ── Step 3: Scan text file contents ──────────────────────────────────────

SECRET_FOUND=0
EXTRACT_DIR="${WORK_DIR}/extracted"
mkdir -p "${EXTRACT_DIR}"

# Extract only text-like files (skip binary extensions)
TEXT_EXTENSIONS="sh|md|yml|yaml|json|tf|tfvars|env|conf|cfg|ini|toml|txt|py|js|ts"

while IFS= read -r entry; do
  # Skip directories
  [[ "${entry}" == */ ]] && continue

  # Only scan text-like extensions
  EXT="${entry##*.}"
  if ! echo "${EXT}" | grep -qiE "^(${TEXT_EXTENSIONS})$"; then
    continue
  fi

  # Skip .example files (safe by design)
  if [[ "${entry}" == *.example ]]; then
    continue
  fi

  # Extract the file quietly
  unzip -p "${ARCHIVE}" "${entry}" > "${EXTRACT_DIR}/current_file" 2>/dev/null || continue

  for rule_def in "${SECRET_PATTERNS[@]}"; do
    RULE_NAME="${rule_def%%|*}"
    RULE_REGEX="${rule_def#*|}"

    # Check each matching line
    while IFS= read -r match_line; do
      # Skip if the line contains a known safe placeholder
      IS_SAFE=0
      for placeholder in "${SAFE_PLACEHOLDERS[@]}"; do
        if echo "${match_line}" | grep -qi "${placeholder}"; then
          IS_SAFE=1
          break
        fi
      done

      # Skip lines with empty assignment (VAR= or VAR="")
      if echo "${match_line}" | grep -qE '=\s*$|=\s*["'"'"']{0,2}\s*$'; then
        IS_SAFE=1
      fi

      # Skip values that are clearly development/example patterns
      if echo "${match_line}" | grep -qE '=.*(-dev|example|localhost|127\.0\.0\.1)[^a-zA-Z0-9]?$'; then
        IS_SAFE=1
      fi

      if [[ "${IS_SAFE}" -eq 0 ]]; then
        printf '[FAIL] Likely secret in %s  [rule: %s] -- VALUE REDACTED\n' \
          "${entry}" "${RULE_NAME}" >&2
        SECRET_FOUND=1
      fi
    done < <(grep -E "${RULE_REGEX}" "${EXTRACT_DIR}/current_file" 2>/dev/null || true)
  done
done < "${ENTRY_LIST}"

# ── Summary ───────────────────────────────────────────────────────────────

OVERALL_FAIL=$(( FORBIDDEN_FOUND + SECRET_FOUND ))

if [[ "${OVERALL_FAIL}" -eq 0 ]]; then
  printf '[OK]  No forbidden paths or high-confidence secrets detected.\n'
  printf '\n'
  printf 'REMINDER: This scan reduces risk but does not guarantee the archive\n'
  printf 'contains no sensitive business data. Review before sharing.\n'
  exit 0
else
  printf '\n' >&2
  printf '[FAIL] Validation failed: %d forbidden path(s), %d secret pattern match(es).\n' \
    "${FORBIDDEN_FOUND}" "${SECRET_FOUND}" >&2

  if [[ "${KEEP_FAILED}" -eq 0 ]]; then
    rm -f "${ARCHIVE}"
    printf '[INFO] Archive deleted: %s\n' "${ARCHIVE}" >&2
    printf '       Use --keep-failed to retain the archive for inspection.\n' >&2
  else
    printf '[WARN] Archive retained (--keep-failed): %s\n' "${ARCHIVE}" >&2
    printf '       Do NOT share this archive.\n' >&2
  fi

  printf '\nCredential rotation recommendation:\n' >&2
  printf '  If this archive was previously shared, rotate all secrets it may contain:\n' >&2
  printf '  - Grafana administrator password (GF_ADMIN_PASSWORD)\n' >&2
  printf '  - OTEL backend ingest key (OTEL_INGEST_API_KEY_BACKEND)\n' >&2
  printf '  - OTEL mobile ingest key (OTEL_INGEST_API_KEY_MOBILE)\n' >&2
  printf '  - Any private keys (*.pem, id_rsa, id_ed25519)\n' >&2
  printf '  - Any DigitalOcean personal access tokens (dop_v1_*)\n' >&2
  exit 1
fi
