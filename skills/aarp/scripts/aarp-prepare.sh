#!/usr/bin/env bash
# aarp-prepare.sh — Prepara una review AARP (port di orchestrator.sh:90-250).
# Classifica il target, crea review-dir stabile + marker di identità, clona se remoto,
# crea lo snapshot read-only con `git archive` (esclude .git e file ignorati/untracked)
# e scrive run.json con target/key/headSha/baseBranch.
#
# Uso: aarp-prepare.sh --target <path|url> [--branch B] [--review-dir D] [--base DIR]
# Output (stdout): path assoluto della review-dir.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=roadmap_helpers.sh
source "${SCRIPT_DIR}/roadmap_helpers.sh"

TARGET_SPEC=""
TARGET_BRANCH_OVERRIDE="${TARGET_BRANCH_OVERRIDE:-}"
REVIEW_DIR_OVERRIDE=""
BASE_DIR="${AARP_REVIEWS_DIR:-$HOME/PI/aarp-reviews}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target|--repository|--repo) TARGET_SPEC="${2:-}"; shift 2 ;;
    --branch|--base-branch|--main-branch) TARGET_BRANCH_OVERRIDE="${2:-}"; shift 2 ;;
    --review-dir) REVIEW_DIR_OVERRIDE="${2:-}"; shift 2 ;;
    --base) BASE_DIR="${2:-}"; shift 2 ;;
    --skill-dir) printf '%s\n' "$SKILL_DIR"; exit 0 ;;
    -h|--help) echo "uso: aarp-prepare.sh --target <path|url> [--branch B] [--review-dir D] [--base DIR] [--skill-dir]"; exit 0 ;;
    *) echo "Argomento sconosciuto: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$TARGET_SPEC" ]] || { echo "Serve --target <path|url>" >&2; exit 2; }

# Pre-flight (fail fast): template e agenti citati devono esistere nella skill.
"${SCRIPT_DIR}/templates-check.sh" "$SKILL_DIR" \
  || { echo "Pre-flight fallito: skill incompleta (template o agenti mancanti)" >&2; exit 1; }

is_remote_target() {
  case "$1" in
    http://*|https://*|ssh://*|git://*|git@*:*|file://*) return 0 ;;
  esac
  [[ "$1" =~ ^([^/:[:space:]]+@)?[^/:[:space:]]+:.+ ]]
}
target_slug() {
  local name="${1##*/}"; name="${name%.git}"; name="${name:-repository}"
  printf '%s' "$name" | tr -cs '[:alnum:]._-' '-' | sed 's/^-*//; s/-*$//'
}
target_hash() { printf '%s' "$1" | cksum | awk '{print $1}'; }
canonical_path() { python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$1"; }
path_is_within() { [[ "$1" == "$2" || "$1" == "$2/"* ]]; }

# --- classificazione target ---
if is_remote_target "$TARGET_SPEC"; then
  TARGET_KIND="git-source"; TARGET_SOURCE="$TARGET_SPEC"
elif [[ -d "$TARGET_SPEC" && "$(git -C "$TARGET_SPEC" rev-parse --is-bare-repository 2>/dev/null || true)" == "true" ]]; then
  TARGET_KIND="git-source"; TARGET_SOURCE="$(canonical_path "$TARGET_SPEC")"
else
  [[ -d "$TARGET_SPEC" ]] || { echo "Target non trovato: ${TARGET_SPEC}" >&2; exit 1; }
  TARGET_KIND="local-checkout"
  TARGET_DIR="$(git -C "$TARGET_SPEC" rev-parse --show-toplevel 2>/dev/null)" \
    || { echo "Target non è un repo Git: ${TARGET_SPEC}" >&2; exit 1; }
  TARGET_DIR="$(canonical_path "$TARGET_DIR")"; TARGET_SOURCE="$TARGET_DIR"
fi

TARGET_SLUG="$(target_slug "$TARGET_SOURCE")"
TARGET_KEY="$(target_hash "${TARGET_KIND}:${TARGET_SOURCE}")"

if [[ -n "$REVIEW_DIR_OVERRIDE" ]]; then
  REVIEW_DIR="$(canonical_path "$REVIEW_DIR_OVERRIDE")"
else
  REVIEW_DIR="$(canonical_path "${BASE_DIR}/${TARGET_SLUG}-${TARGET_KEY}")"
fi
if [[ "$TARGET_KIND" == "local-checkout" ]] && path_is_within "$REVIEW_DIR" "$TARGET_DIR"; then
  echo "La review-dir deve stare fuori dal target locale: ${REVIEW_DIR}" >&2; exit 1
fi
mkdir -p "$REVIEW_DIR"

MARKER="${REVIEW_DIR}/.aarp-target-key"
if [[ -f "$MARKER" && "$(cat "$MARKER")" != "${TARGET_KIND}:${TARGET_KEY}" ]]; then
  echo "La review-dir appartiene a un altro target: ${REVIEW_DIR}" >&2; exit 1
fi
printf '%s\n' "${TARGET_KIND}:${TARGET_KEY}" > "$MARKER"

# --- clone per target remoti ---
if [[ "$TARGET_KIND" == "git-source" ]]; then
  TARGET_DIR="${REVIEW_DIR}/repository"
  if [[ -e "$TARGET_DIR" ]]; then
    git -C "$TARGET_DIR" rev-parse --show-toplevel >/dev/null 2>&1 \
      || { echo "Checkout esistente ma non è un repo Git: ${TARGET_DIR}" >&2; exit 1; }
    ORIGIN_URL="$(git -C "$TARGET_DIR" remote get-url origin 2>/dev/null || true)"
    [[ "$ORIGIN_URL" == "$TARGET_SOURCE" ]] \
      || { echo "Checkout esistente con origin diverso: ${TARGET_DIR}" >&2; exit 1; }
  else
    git clone "$TARGET_SOURCE" "$TARGET_DIR"
  fi
fi

REPORTS_DIR="${REVIEW_DIR}/reports"; mkdir -p "$REPORTS_DIR"
AUDIT_DIR="${REVIEW_DIR}/source"
HEAD_SHA="$(git -C "$TARGET_DIR" rev-parse HEAD 2>/dev/null || echo '')"

# --- snapshot read-only (git archive: niente .git, niente file ignorati) ---
if [[ ! -d "$AUDIT_DIR" ]]; then
  mkdir -p "$AUDIT_DIR"
  if ! git -C "$TARGET_DIR" archive --format=tar HEAD | tar -x -C "$AUDIT_DIR"; then
    echo "Snapshot fallito (repo senza commit?): ${TARGET_DIR}" >&2; exit 1
  fi
fi

BASE_BRANCH="$(roadmap_detect_base_branch "$TARGET_DIR" "${REPORTS_DIR}/ROADMAP.md" 2>/dev/null || echo main)"

python3 - "$REVIEW_DIR" "$TARGET_KIND" "$TARGET_SOURCE" "$TARGET_DIR" "$REPORTS_DIR" "$AUDIT_DIR" "$TARGET_KEY" "$HEAD_SHA" "$BASE_BRANCH" "$TARGET_BRANCH_OVERRIDE" <<'PY'
import json, sys
rec, kind, source, tdir, reports, audit, key, sha, base, override = sys.argv[1:11]
json.dump({
    "target": source, "kind": kind, "key": key,
    "targetDir": tdir, "reviewDir": rec, "reportsDir": reports, "sourceDir": audit,
    "headSha": sha, "baseBranch": base, "branchOverride": override,
}, open(rec + "/run.json", "w"), indent=2)
PY

printf '%s\n' "$REVIEW_DIR"
