---
name: aarp
license: MIT
compatibility: "bash >= 4, git >= 2.20, rsync; pi-subagents per gli agenti"
description: "Pipeline AARP: audit multi-agente di un repository Git (context mapping, 6 audit in parallelo, ROADMAP P0/P1/P2) e remediation guidata con gate umani. Orchestra context-mapper, 6 auditor (ux-ui, security, db, code-quality, devops, doc-coverage), roadmap-director, developer, code-reviewer, qa-test, documentation-architect. Usa quando l'utente vuole auditare/revisionare un repo con AARP, o invoca /skill:aarp."
---

# AARP — Agentic Audit & Roadmap Pipeline

Orchestrazione nativa in pi. Le fasi 0-3 leggono **solo lo snapshot** (mai il target reale);
il target si tocca solo in Fase 3, dopo i gate H2+H3. Git e aggiornamento ROADMAP sono
**deterministici nel parent** (bash), mai delegati all'LLM.

```
SKILL_DIR=$({baseDir}/scripts/aarp-prepare.sh --skill-dir)
```

`SKILL_DIR` è la directory della skill (`scripts/`, `workflows/`, `agents/`, `templates/` vivono qui):
il path della skill te lo dà pi, `aarp-prepare.sh --skill-dir` lo ricava da `dirname $0`.
Passalo ai workflow come `args.templatesDir`.

## Input

`/skill:aarp <path|url> [--branch B] [--review-dir D] [--only-doc]`

- `<path|url>`: checkout locale o URL Git (https/ssh/git/file).
- `<RD>`: review-dir restituita da Fase 0. `<SRC>=<RD>/source`, `<REP>=<RD>/reports`.

## Agenti orchestrati

| Fase | Agenti |
|---|---|
| 1 Doc | `documentation-architect` |
| 2 Audit | `context-mapper`, `ux-ui-auditor`, `security-auditor`, `db-auditor`, `code-quality-auditor`, `devops-auditor`, `doc-coverage-auditor`, `roadmap-director` |
| 3 Remediation | `developer`, `code-reviewer`, `qa-test` |

Altri agenti del progetto, **nella skill ma non orchestrati da `workflows/audit.js`** (invocabili a mano o dal task, definizione in `agents/`):

| Agente | Ruolo |
|---|---|
| `aarp-scout` | Esplorazione read-only (mappa codebase / scheletro PROJECT_CONTEXT, fase 0) |
| `aarp-researcher` | Ricerca web su un argomento (fase 0) |
| `engineering-director` | Legge i report in `<cwd>/.aarp/reports/` e pubblica una issue GitLab per finding (post-remediation) |
| `plan` | Pianificazione infrastruttura (produzione piani/spec per agenti) |

Tutti e 16 gli agenti del progetto vivono in `agents/` (dal 2026-10-25; prima erano in `~/.pi/agent/agents/` fuori dal bundle).

## Fase 0 — Prepare

1. Esegui e cattura l'output:
   ```
   RD=$("${SKILL_DIR}/scripts/aarp-prepare.sh" --target <path|url> [--branch B] [--review-dir D])
   ```
   Stampa `<RD>`. Lo script esegue prima il pre-flight `scripts/templates-check.sh <SKILL_DIR>`:
   se un template o un agente citato manca nel pacchetto, fallisce senza creare lo snapshot.
   Errori → fermati e riportali.
2. Leggi `<RD>/run.json`: `targetDir`, `reportsDir`, `sourceDir`, `headSha`, `baseBranch`.
3. Se un `run.json` precedente aveva `headSha` diverso → **H0-bis**: chiedi se rigenerare lo
   snapshot (`rm -rf <SRC>` e ri-esegui prepare). Default: N.

## Fase 1 — Documentazione (opzionale)

Solo con `--only-doc` o se l'utente la chiede.

1. Rileva docs in `<SRC>` (`docs/`, `doc/`, `documents/`).
   - **H0**: se assenti, chiedi se generare la documentazione; default N.
2. Se sì: lancia `documentation-architect` con `cwd: <SRC>` e staging `<RD>/reports/documentation`.
   Valida i 4 file (`ARCHITECTURE.md`, `ADMIN_GUIDE.md`, `USER_GUIDE.md`, `API_REF.md`); retry mirato sui mancanti.
3. **H1**: chiedi se copiare il bundle in un branch documentale; default N.
   Se sì: `git -C <targetDir> worktree add -b docs/documentation-<ts> <RD>/worktrees/doc <baseBranch>`,
   copia i `.md`, commit `docs: refresh generated documentation`, `git worktree remove`. **Nessun push.**
4. Se `--only-doc`: termina.

## Fase 2 — Audit (fasi 1-3)

1. Calcola `skip` con i checkpoint: per ogni report atteso in `<REP>`, se `report-check.sh` dà 0 → mettilo in `skip`.
2. Lancia UN workflow:
   ```
   subagent({ workflow: SKILL_DIR + "/workflows/audit.js",
              args: { rd: "<RD>", templatesDir: SKILL_DIR, skip: [ ... ] },
              cwd: "<SRC>" })
   ```
   Produce `<REP>/PROJECT_CONTEXT.md`, i 6 `AUDIT_*.md`, `<REP>/ROADMAP.md`.
3. Verifica ogni report con `report-check.sh`; se uno fallisce, segnala e fermati (niente Fase 3).

## Fase 3 — Remediation (gate umano)

1. **H2**: mostra i task aperti per priorità (`roadmap_next_task_preview`) e `<REP>/ROADMAP.md`;
   **chiedi conferma esplicita** per entrare in Fase 3; default N.
2. Prepara l'ambiente nel parent:
   ```
   export ROADMAP_REPORT="<REP>/ROADMAP.md"
   source "${SKILL_DIR}/scripts/roadmap_helpers.sh"
   # skip già scartati in run precedenti (persistiti in run.json)
   skipped_csv=$(python3 -c "import json;print(','.join(json.load(open('<RD>/run.json')).get('skipped',[])))")
   ```
3. Loop finché ci sono task o l'utente esce:
   a. `preview=$(roadmap_next_task_preview "<skipped_csv>")`; se vuoto → fine.
   b. **H3**: chiedi `s` / `skip` / `exit` (default exit).
      `skip` → aggiungi l'ID a `skipped_csv` e **persistilo** in `<RD>/run.json` (`skipped: [...]`), poi ripeti.
   c. `git -C <targetDir> status --porcelain` non vuoto → fermati.
   d. Determina `prefix` = `roadmap_task_branch_prefix <P0|P1|P2>`; `id` = `roadmap_task_id_from_preview "$preview"`.
      Crea un worktree isolato (un writer per worktree):
      ```
      git -C <targetDir> worktree add -b <prefix><slug> <RD>/worktrees/<slug> <baseBranch>
      ```
   e. Lancia:
      ```
      subagent({ workflow: SKILL_DIR + "/workflows/remediate.js",
                 args: { templatesDir: SKILL_DIR,
                         tasks: [ { id: "<id>", title: "<titolo>", branch: "<prefix><slug>",
                                   worktree: "<RD>/worktrees/<slug>", scope: "<scope da ROADMAP.md>" } ] },
                 cwd: "<RD>" })
      ```
   f. Leggi il verdetto della review dal risultato del workflow (o dal report):
      - `APPROVED` → **H4** (push del branch? default N; se sì `git push origin <branch>`).
        Poi **H5 informato**: mostra verdetto review, esito QA e `git -C <targetDir> diff --stat <baseBranch>...<branch>`,
        **poi** chiedi il merge (default N). Se sì: `git -C <targetDir> checkout <baseBranch> && git -C <targetDir> merge --no-ff <branch>`
        → `mark_roadmap_task_merged <id>` → `git -C <targetDir> branch -d <branch>` e `git -C <targetDir> worktree remove <RD>/worktrees/<slug>`.
        **H6** (push base? default N; se sì `git -C <targetDir> push origin <baseBranch>`, con errore gestito).
      - `CHANGES_REQUESTED` → torna a (e) passando il feedback del reviewer nel `task` (max 3 tentativi).
      - `BLOCKED` → fermati e chiedi all'utente (vero HITL).
   g. Riprendi da (a).

4. Output finale: tabella dei task (`merged`/`skipped`/`blocked`), path dei report, `<RD>/run.json`.

## Regole

- Non modificare il target prima di H2+H3. Fasi 0-3 girano su `<SRC>`.
- Nessun `push`/`merge` senza gate esplicito. Default di ogni gate: **N** (tranne H5: N anche lì).
- La ROADMAP la aggiorna solo `mark_roadmap_task_merged` (deterministico): non far scrivere stato all'LLM.
- Se un agente chiede una decisione a metà lavoro, risponde il **parent** (non rimandare all'utente un loop infinito).
- Nel campo `workflow:` di `subagent` usa il path assoluto `SKILL_DIR + "/workflows/..."`:
  `~` non viene espanso e il path relativo viene risolto contro il `cwd`.
- Su errore di workflow/agente: fermati, riporta stato esatto + worktree, non riprovare alla cieca.
- **Recuperare un task saltato**: resta `[ ]` in ROADMAP. Basta chiederlo per ID (es. "esegui TASK-P1-03") oppure rimuovere il suo ID da `skipped` in `<RD>/run.json` e ripartire.

## Riferimenti

- `workflows/audit.js` — fasi 1-3 (context → 6 audit ∥ → ROADMAP)
- `workflows/remediate.js` — fase 3, per task (dev → QA → review)
- `scripts/aarp-prepare.sh`, `scripts/report-check.sh`, `scripts/roadmap_helpers.sh`, `scripts/templates-check.sh`
- Agenti del pacchetto: `agents/`; template: `templates/`