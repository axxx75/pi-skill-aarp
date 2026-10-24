#!/usr/bin/env bash
# smoke.sh — self-check del pacchetto pi-skill-aarp.
# Verifica: frontmatter YAML, script eseguibili, pre-flight template/agenti,
# assenza di path assoluti, self-test di report-check.sh, fail-fast di aarp-prepare.sh.
# Uso: bash tests/smoke.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DIR="${ROOT}/skills/aarp"
SCRIPTS="${SKILL_DIR}/scripts"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
ko() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; }

# 1. Frontmatter YAML valido per agenti e SKILL.md.
python3 - "$ROOT" <<'PY'
import pathlib, sys, yaml
root = pathlib.Path(sys.argv[1])
bad = []
files = sorted((root / "skills/aarp/agents").glob("*.md")) + [root / "skills/aarp/SKILL.md"]
for f in files:
    text = f.read_text()
    if not text.startswith("---\n"):
        bad.append(f"{f}: manca il frontmatter"); continue
    end = text.find("\n---", 4)
    if end < 0:
        bad.append(f"{f}: frontmatter non chiuso"); continue
    try:
        meta = yaml.safe_load(text[4:end])
    except yaml.YAMLError as e:
        bad.append(f"{f}: YAML non valido: {e}"); continue
    if not isinstance(meta, dict):
        bad.append(f"{f}: frontmatter non è una mappa"); continue
    for key in ("name", "description"):
        if not str(meta.get(key) or "").strip():
            bad.append(f"{f}: campo '{key}' mancante o vuoto")
    if f.parent.name == "agents" and meta.get("name") != f.stem:
        bad.append(f"{f}: name '{meta.get('name')}' != {f.stem}")
if bad:
    print("\n".join(bad)); sys.exit(1)
print(f"frontmatter ok ({len(files)} file)")
PY
if [[ $? -eq 0 ]]; then ok "frontmatter YAML (12 agenti + SKILL.md)"; else ko "frontmatter YAML"; fi

# 2. Solo i 12 agenti della pipeline, niente extra.
expected="code-quality-auditor code-reviewer context-mapper db-auditor developer devops-auditor doc-coverage-auditor documentation-architect qa-test roadmap-director security-auditor ux-ui-auditor"
actual="$(cd "${SKILL_DIR}/agents" && ls *.md | sed 's/\.md$//' | sort | tr '\n' ' ' | sed 's/ $//')"
if [[ "$actual" == "$expected" ]]; then ok "12 agenti attesi, nessun extra"; else ko "agenti: attesi [$expected], trovati [$actual]"; fi

# 3. Script eseguibili.
for s in aarp-prepare.sh report-check.sh roadmap_helpers.sh templates-check.sh; do
  if [[ -x "${SCRIPTS}/${s}" ]]; then ok "eseguibile: ${s}"; else ko "non eseguibile: ${s}"; fi
done

# 4. Pre-flight templates-check sul pacchetto reale.
if "${SCRIPTS}/templates-check.sh" "$SKILL_DIR"; then ok "templates-check sul pacchetto"; else ko "templates-check sul pacchetto"; fi

# 5. Nessun path assoluto o path globale dei template nel pacchetto.
# I pattern sono composti a runtime: il file di test non deve contenere i letterali cercati.
home_pat="$(printf '/%s/' home)"
tpl_pat="agents_templ""ates"
hits="$(grep -RIn --exclude-dir=.git --exclude=smoke.sh -e "$home_pat" -e "$tpl_pat" "$ROOT" || true)"
if [[ -z "$hits" ]]; then ok "nessun path assoluto utente né path globale template"; else ko "path proibiti trovati:"$'\n'"$hits"; fi

# 6. I workflow ricevono la radice del pacchetto.
for w in audit.js remediate.js; do
  if grep -q 'args.templatesDir' "${SKILL_DIR}/workflows/${w}"; then ok "workflow ${w} usa args.templatesDir"; else ko "workflow ${w} non usa args.templatesDir"; fi
done

# 7. aarp-prepare.sh --skill-dir stampa la directory della skill.
if [[ "$("${SCRIPTS}/aarp-prepare.sh" --skill-dir)" == "$SKILL_DIR" ]]; then ok "aarp-prepare.sh --skill-dir"; else ko "aarp-prepare.sh --skill-dir"; fi

# 8. report-check.sh self-test.
good="${TMP}/good.md"; printf '# Report\n\n## Executive Database Summary\n\nok\n' > "$good"
if "${SCRIPTS}/report-check.sh" "$good" "## Executive Database Summary" 2>/dev/null; then ok "report-check accetta un report valido"; else ko "report-check su report valido"; fi
if ! "${SCRIPTS}/report-check.sh" "$good" "## Verification" 2>/dev/null; then ok "report-check rifiuta una sezione mancante"; else ko "report-check su sezione mancante"; fi
bad="${TMP}/bad.md"; printf '# Report\n\n## Executive Database Summary\n\nTODO: compilare\n' > "$bad"
if ! "${SCRIPTS}/report-check.sh" "$bad" "## Executive Database Summary" 2>/dev/null; then ok "report-check rifiuta i placeholder"; else ko "report-check su placeholder"; fi
if ! "${SCRIPTS}/report-check.sh" "${TMP}/nope.md" "## X" 2>/dev/null; then ok "report-check rifiuta un report assente"; else ko "report-check su report assente"; fi

# 9. Fail-fast: template mancante → templates-check e aarp-prepare falliscono prima dello snapshot.
broken="${TMP}/pkg"; cp -R "$ROOT" "$broken"; rm "${broken}/skills/aarp/templates/AUDIT_APPSEC.template.md"
if ! "${broken}/skills/aarp/scripts/templates-check.sh" "${broken}/skills/aarp" 2>/dev/null; then ok "templates-check fallisce con un template mancante"; else ko "templates-check non rileva il template mancante"; fi
rm "${broken}/skills/aarp/agents/qa-test.md"
if ! "${broken}/skills/aarp/scripts/templates-check.sh" "${broken}/skills/aarp" 2>/dev/null; then ok "templates-check fallisce con un agente mancante"; else ko "templates-check non rileva l'agente mancante"; fi
repo="${TMP}/repo"; mkdir -p "$repo"; git -C "$repo" init -q; git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
base="${TMP}/reviews"
if ! "${broken}/skills/aarp/scripts/aarp-prepare.sh" --target "$repo" --base "$base" >/dev/null 2>&1; then ok "aarp-prepare.sh fa fail-fast sul pre-flight"; else ko "aarp-prepare.sh non fa fail-fast"; fi
if [[ ! -e "$base" ]]; then ok "nessuno snapshot creato prima del pre-flight"; else ko "review-dir creata nonostante il pre-flight fallito"; fi

printf '\n%s\n' "----------------------------------------"
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]] && { echo "OK"; exit 0; } || { echo "FAILED"; exit 1; }
