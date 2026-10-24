#!/usr/bin/env bash
# templates-check.sh — Pre-flight AARP: verifica che template e agenti citati esistano nella skill.
# Scansiona i workflow (mappa [key, agente, report, template]) e i prompt degli agenti.
# Uso: templates-check.sh <skill-dir>
# Exit: 0 = skill completa, 1 = riferimento mancante, 2 = uso errato.
set -euo pipefail

[[ $# -eq 1 ]] || { echo "uso: templates-check.sh <skill-dir>" >&2; exit 2; }

SKILL="$1"
WF_DIR="${SKILL}/workflows"
AGENTS_DIR="${SKILL}/agents"
TPL_DIR="${SKILL}/templates"

for d in "$WF_DIR" "$AGENTS_DIR" "$TPL_DIR"; do
  [[ -d "$d" ]] || { echo "templates-check: directory mancante: $d" >&2; exit 1; }
done
shopt -s nullglob
workflows=("${WF_DIR}"/*.js)
[[ ${#workflows[@]} -gt 0 ]] || { echo "templates-check: nessun workflow in $WF_DIR" >&2; exit 1; }

status=0

# Template citati dai workflow o dagli agenti (es. AUDIT_APPSEC.template.md).
while IFS= read -r tpl; do
  [[ -f "${TPL_DIR}/${tpl}" ]] || { echo "templates-check: template mancante: ${tpl}" >&2; status=1; }
done < <(grep -rhoE '[A-Z][A-Z0-9_]+\.template\.md' "$WF_DIR" "$AGENTS_DIR" | sort -u)

# Agenti citati dai workflow: sia `agent: "nome"` sia le mappe `["key", "nome", ...]`.
while IFS= read -r agent; do
  [[ -f "${AGENTS_DIR}/${agent}.md" ]] || { echo "templates-check: agente mancante: ${agent}" >&2; status=1; }
done < <(
  {
    grep -hoE 'agent: *"[a-z0-9-]+"' "${workflows[@]}" | sed -E 's/.*"(.*)"/\1/'
    grep -hoE '\["[a-z0-9]+", *"[a-z0-9-]+"' "${workflows[@]}" | sed -E 's/.*", *"(.*)"/\1/'
  } | sort -u
)

exit "$status"
