#!/usr/bin/env bash
# report-check.sh — Checkpoint semantico di un report AARP.
# Verifica: file esiste, non vuoto, contiene ogni sezione obbligatoria richiesta
# (match letterale) e non contiene placeholder di template non sostituiti.
#
# Uso: report-check.sh <report> <sezione-obbligatoria> [<sezione> ...]
# Esempio: report-check.sh reports/AUDIT_DATABASE.md "## Executive Database Summary" "## Verification"
# Exit: 0 = ok, 1 = non valido, 2 = uso errato.
set -euo pipefail

[[ $# -ge 2 ]] || { echo "uso: report-check.sh <report> <sezione> [<sezione> ...]" >&2; exit 2; }

report="$1"; shift
[[ -f "$report" ]] || { echo "report-check: assente: $report" >&2; exit 1; }
[[ -s "$report" ]] || { echo "report-check: vuoto: $report" >&2; exit 1; }

status=0
for section in "$@"; do
  if ! grep -qF -- "$section" "$report"; then
    echo "report-check: sezione mancante \"$section\" in $report" >&2
    status=1
  fi
done

# Placeholder di template non sostituiti.
if grep -qE '<Short |<Scenario|YYYY-MM-DD|TASK-P[012]-XX|\[TBD\]|TODO:' "$report"; then
  echo "report-check: placeholder non sostituiti in $report" >&2
  status=1
fi

exit "$status"
