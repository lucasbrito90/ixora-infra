#!/usr/bin/env bash
# ============================================================
# package-source-safe.sh
#
# Create a source archive that is safe to share.
# Excludes: .git/, secrets, Terraform state/plans/vars,
#           runtime-generated files, and private keys.
#
# Safe example files (e.g. collector/.env.example) are INCLUDED.
#
# Usage:
#   ./scripts/package-source-safe.sh
#   ./scripts/package-source-safe.sh --output /tmp/ixora-infra-safe.zip
#   ./scripts/package-source-safe.sh --output /tmp/out.zip --force
#
# Options:
#   --output <path>  Output archive path (default: /tmp/ixora-infra-safe-<date>.zip)
#   --force          Overwrite an existing archive
#   --help           Show this help
#
# Note: a successful run reduces risk of accidental secret exposure,
# but does not guarantee the archive contains no sensitive business data.
# Always review the archived file list before sharing.
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── Argument parsing ──────────────────────────────────────────────────────

OUTPUT_PATH=""
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)  OUTPUT_PATH="$2"; shift 2 ;;
    --force)   FORCE=1;          shift ;;
    --help|-h)
      grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      printf 'ERROR: Unknown argument: %s\n' "$1" >&2
      printf 'Run with --help for usage.\n' >&2
      exit 1
      ;;
  esac
done

# Default output path
if [[ -z "${OUTPUT_PATH}" ]]; then
  DATE_STAMP="$(date +%Y%m%d-%H%M%S)"
  OUTPUT_PATH="/tmp/ixora-infra-safe-${DATE_STAMP}.zip"
fi

# ── Overwrite guard ───────────────────────────────────────────────────────

if [[ -f "${OUTPUT_PATH}" && "${FORCE}" -eq 0 ]]; then
  printf 'ERROR: Output file already exists: %s\n' "${OUTPUT_PATH}" >&2
  printf '       Use --force to overwrite.\n' >&2
  exit 1
fi

# ── Temp directory (cleaned up on exit) ──────────────────────────────────

WORK_DIR="$(mktemp -d /tmp/ixora-pkg-XXXXXX)"
FILELIST="${WORK_DIR}/filelist.txt"

cleanup() {
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

# ── Forbidden path patterns (denylist) ───────────────────────────────────
#
# These are checked against the file list BEFORE the archive is finalized.
# Format: ERE regex matched against each candidate path relative to REPO_ROOT.
#
FORBIDDEN_PATTERNS=(
  '(^|/)\.git/'
  '(^|/)\.git$'
  '(^|/)collector/\.env$'
  '(^|/)\.env$'
  '(^|/)\.env\.'
  '(^|/)terraform\.tfvars$'
  '(^|/)terraform\.tfvars\.json$'
  '[^.].*\.auto\.tfvars$'
  '[^.].*\.auto\.tfvars\.json$'
  '\.tfstate$'
  '\.tfstate\.'
  '\.tfplan$'
  '(^|/)tfplan$'
  '(^|/)plan\.json$'
  '(^|/)plan.*\.json$'
  '(^|/)\.(terraform)/'
  '(^|/)crash\.log$'
  '(^|/)crash\.'
  '\.pem$'
  '\.key$'
  '(^|/)id_rsa$'
  '(^|/)id_ed25519$'
  '(^|/)id_ecdsa$'
  '(^|/)id_dsa$'
)

# ── Build candidate file list ─────────────────────────────────────────────

cd "${REPO_ROOT}"

printf '[INFO] Building file list from: %s\n' "${REPO_ROOT}"

if git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf '[INFO] Using git ls-files --cached (tracked files only)\n'
  # Tracked files only — never include untracked local files from the worktree.
  # The denylist and archive validator provide defense in depth.
  git ls-files --cached > "${FILELIST}"
else
  printf '[WARN] Not a git repository; using find\n'
  find . -type f \
    -not -path './.git/*' \
    -not -path './.git' \
    | sed 's|^\./||' > "${FILELIST}"
fi

TOTAL_CANDIDATES="$(wc -l < "${FILELIST}")"
printf '[INFO] Candidate files before denylist: %d\n' "${TOTAL_CANDIDATES}"

# ── Apply denylist ────────────────────────────────────────────────────────

CLEAN_LIST="${WORK_DIR}/clean.txt"
BLOCKED_LIST="${WORK_DIR}/blocked.txt"

: > "${CLEAN_LIST}"
: > "${BLOCKED_LIST}"

while IFS= read -r filepath; do
  BLOCKED=0
  # .example files are explicitly safe and must never be excluded
  if [[ "${filepath}" == *.example ]]; then
    printf '%s\n' "${filepath}" >> "${CLEAN_LIST}"
    continue
  fi
  for pattern in "${FORBIDDEN_PATTERNS[@]}"; do
    if echo "${filepath}" | grep -qE "${pattern}"; then
      BLOCKED=1
      printf '%s  [matched: %s]\n' "${filepath}" "${pattern}" >> "${BLOCKED_LIST}"
      break
    fi
  done
  if [[ "${BLOCKED}" -eq 0 ]]; then
    printf '%s\n' "${filepath}" >> "${CLEAN_LIST}"
  fi
done < "${FILELIST}"

BLOCKED_COUNT="$(wc -l < "${BLOCKED_LIST}")"
CLEAN_COUNT="$(wc -l < "${CLEAN_LIST}")"

if [[ "${BLOCKED_COUNT}" -gt 0 ]]; then
  printf '[INFO] %d file(s) excluded by denylist:\n' "${BLOCKED_COUNT}"
  while IFS= read -r line; do
    printf '  EXCLUDED: %s\n' "${line}"
  done < "${BLOCKED_LIST}"
fi

if [[ "${CLEAN_COUNT}" -eq 0 ]]; then
  printf 'ERROR: No files remain after denylist filtering.\n' >&2
  exit 1
fi

# ── Verify safe example files are included ────────────────────────────────

SAFE_EXAMPLES=(
  "collector/.env.example"
  "opentofu/staging/terraform.tfvars.example"
)

for example in "${SAFE_EXAMPLES[@]}"; do
  if [[ -f "${REPO_ROOT}/${example}" ]]; then
    if grep -qF "${example}" "${CLEAN_LIST}"; then
      printf '[OK]  Safe example included: %s\n' "${example}"
    else
      printf '[WARN] Safe example was excluded (check denylist): %s\n' "${example}"
    fi
  fi
done

# ── Create the archive ────────────────────────────────────────────────────

printf '[INFO] Creating archive: %s\n' "${OUTPUT_PATH}"

# Ensure output directory exists
OUTPUT_DIR="$(dirname "${OUTPUT_PATH}")"
mkdir -p "${OUTPUT_DIR}"

# Build archive from clean list
zip -q "${OUTPUT_PATH}" --names-stdin < "${CLEAN_LIST}"
printf '[OK]  Archive created: %s\n' "${OUTPUT_PATH}"
printf '[OK]  Files packaged: %d\n' "${CLEAN_COUNT}"

# ── Run built-in archive validation ──────────────────────────────────────

printf '[INFO] Running archive validation...\n'

# Call validate-source-archive.sh if it exists next to this script
VALIDATOR="${SCRIPT_DIR}/validate-source-archive.sh"
if [[ -x "${VALIDATOR}" ]]; then
  if "${VALIDATOR}" "${OUTPUT_PATH}"; then
    printf '[OK]  Archive validation passed\n'
  else
    printf 'ERROR: Archive validation FAILED. Archive deleted.\n' >&2
    rm -f "${OUTPUT_PATH}"
    exit 1
  fi
else
  printf '[WARN] validate-source-archive.sh not found - skipping deep validation\n'
fi

printf '\n'
printf 'Archive path:   %s\n' "${OUTPUT_PATH}"
printf 'Files packaged: %d\n' "${CLEAN_COUNT}"
printf '\n'
printf 'REMINDER: Review the file list before sharing:\n'
printf '  unzip -l %s\n' "${OUTPUT_PATH}"
printf '\n'
printf 'A successful packaging run reduces the risk of accidental secret exposure,\n'
printf 'but does not guarantee the archive contains no sensitive business data.\n'
