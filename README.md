# pi-skill-aarp

Skill per [pi](https://pi.dev) che implementa la **pipeline AARP**: audit multi-agente di un
repository Git (context mapping, 6 audit in parallelo, ROADMAP P0/P1/P2) e remediation guidata con
gate umani (H0-H6).

Il pacchetto è autosufficiente: skill, workflow, script, i **12 agenti** della pipeline e gli **11
template** dei report vivono qui dentro. Nessun path assoluto: la radice del pacchetto la ricava
`skills/aarp/scripts/aarp-prepare.sh` da `dirname $0` e la passa ai workflow come `args.templatesDir`.
Tutto ciò che è bundled (agenti, template, workflow, script) sta **dentro** la skill dir.

## Requirements

| Componente | Versione / note | Obbligatorio |
|---|---|---|
| `pi` | ≥ 1.4 | sì |
| `pi-subagents` | estensione con supporto `pi.subagents.agents` | sì |
| `git` | ≥ 2.20 | sì |
| `bash` | ≥ 4 (`nullglob`, process substitution) | sì |
| `python3` | ≥ 3.8 (JSON di `run.json`, frontmatter nei test) | sì |
| `PyYAML` | solo per `tests/smoke.sh` | no, solo test |

Nessuna chiamata di rete propria: il traffico è quello degli agenti LLM che pi lancia.

## Install

Da path locale (il pacchetto è caricato dal path, senza copiarlo):

```bash
pi install /percorso/pi-skill-aarp
```

Da repository Git, quando sarà pubblicato:

```bash
pi install git:github.com/<utente>/pi-skill-aarp@v1.0.0
```

Verifica:

```bash
pi list                                  # deve comparire pi-skill-aarp
pi -p "elenca i nomi delle skill che vedi"
```

La skill si attiva da sola quando la richiesta la riguarda, oppure in modo esplicito:
`/skill:aarp /percorso/repo`.

### Struttura

```text
pi-skill-aarp/
├── skills/aarp/                 # la skill è autosufficiente: {baseDir} = skills/aarp
│   ├── SKILL.md                 # orchestrazione (nessun path assoluto)
│   ├── agents/                  # 12 agenti della pipeline (manifest pi.subagents.agents)
│   ├── templates/               # 11 template dei report
│   ├── workflows/
│   │   ├── audit.js             # context → 6 audit ∥ → ROADMAP
│   │   └── remediate.js         # developer → qa-test → code-reviewer
│   └── scripts/
│       ├── aarp-prepare.sh      # review-dir + snapshot; pre-flight templates-check
│       ├── templates-check.sh   # template e agenti citati esistono?
│       ├── report-check.sh      # checkpoint semantico dei report
│       └── roadmap_helpers.sh   # parsing/stato ROADMAP
└── tests/smoke.sh
```

## Verify

```bash
bash tests/smoke.sh
```

Cosa fa:

- frontmatter YAML valido per i 12 agenti e per `SKILL.md` (`name` + `description` non vuoti);
- esattamente i 12 agenti della pipeline, nessun extra;
- script eseguibili;
- `templates-check.sh` verde sul pacchetto;
- `grep` vuoto su path assoluti utente e sul vecchio path globale dei template;
- self-test di `report-check.sh` (report valido, sezione mancante, placeholder, file assente);
- fail-fast: con un template o un agente rimosso, `templates-check.sh` e `aarp-prepare.sh` falliscono
  **prima** di creare la review-dir.

Output atteso: `OK` e exit code 0.

### Test in ambiente isolato

```bash
mkdir -p /tmp/pitest-aarp
ln -s ~/.pi/agent/auth.json /tmp/pitest-aarp/auth.json
ln -s ~/.pi/agent/models-store.json /tmp/pitest-aarp/models-store.json
printf '{"packages":["/percorso/pi-skill-aarp"]}\n' > /tmp/pitest-aarp/settings.json
PI_CODING_AGENT_DIR=/tmp/pitest-aarp pi -p "elenca i nomi delle skill che vedi"
```

Non lanciare un audit completo per verificare l'installazione: costa. Bastano il caricamento della
skill, la presenza degli agenti e il pre-flight.

## Usage

```text
/skill:aarp <path|url> [--branch B] [--review-dir D] [--only-doc]
```

| Fase | Cosa fa | Agenti |
|---|---|---|
| 0 Prepare | `aarp-prepare.sh`: pre-flight, clone se remoto, snapshot `git archive`, `run.json` | — |
| 1 Doc | documentazione opzionale (H0/H1) | `documentation-architect` |
| 2 Audit | `audit.js`: context + 6 audit in parallelo + ROADMAP | `context-mapper`, 6 auditor, `roadmap-director` |
| 3 Remediation | `remediate.js` per task, con gate H2-H6 | `developer`, `qa-test`, `code-reviewer` |

Mappa dei template usata dai workflow (`key → agente → report → template`):

| key | agente | report | template |
|---|---|---|---|
| `context` | `context-mapper` | `PROJECT_CONTEXT.md` | `PROJECT_CONTEXT.template.md` |
| `ux` | `ux-ui-auditor` | `AUDIT_UX_PERF.md` | `AUDIT_UX_PERF.template.md` |
| `sec` | `security-auditor` | `AUDIT_APPSEC.md` | `AUDIT_APPSEC.template.md` |
| `db` | `db-auditor` | `AUDIT_DATABASE.md` | `AUDIT_DATABASE.template.md` |
| `quality` | `code-quality-auditor` | `AUDIT_QUALITY.md` | `AUDIT_QUALITY.template.md` |
| `infra` | `devops-auditor` | `AUDIT_INFRA.md` | `AUDIT_INFRA.template.md` |
| `doc` | `doc-coverage-auditor` | `AUDIT_DOC_COVERAGE.md` | `AUDIT_DOC_COVERAGE.template.md` |
| `roadmap` | `roadmap-director` | `ROADMAP.md` | `ROADMAP.template.md` |
| `dev` | `developer` | — | — |
| `qa` | `qa-test` | `TEST_REPORT.md` | `TEST_REPORT.template.md` |
| `review` | `code-reviewer` | `REVIEW_REPORT.md` | `REVIEW_REPORT.template.md` |

`TASK_ISSUE.template.md` e `AUDIT_DOCS.template.md` **non** sono inclusi: il primo è usato solo da
`engineering-director`, fuori dalla pipeline; il secondo non è citato da nessun agente né workflow.

## Troubleshooting

| Sintomo | Causa | Rimedio |
|---|---|---|
| `Pre-flight fallito: pacchetto incompleto` | manca un template o un agente citato dai workflow | ripristina il file o aggiorna la mappa; `templates-check.sh <pacchetto>` dice quale |
| `templates-check: agente mancante: X` | agente rimosso/rinominato in `agents/` | allinea il nome nel workflow |
| `args.templatesDir ... mancante` | workflow lanciato senza la radice del pacchetto | passa `templatesDir: SKILL_DIR` |
| `La review-dir appartiene a un altro target` | marker `.aarp-target-key` di un altro repo | usa un'altra `--review-dir` o `--base` |
| `Snapshot fallito (repo senza commit?)` | repo vuoto | fai almeno un commit nel target |
| `report-check: sezione mancante` | l'agente ha saltato una sezione del template | rilancia lo step o correggi il report |
| Skill `aarp` duplicata (pacchetto + copia in `~/.pi/agent/skills/aarp`) | pi carica la **prima** trovata e stampa un warning di collisione; gli agenti del pacchetto hanno priorità **sotto** `~/.pi/agent/agents/` | rimuovi la copia vecchia e i 12 agenti globali dopo la verifica |

## Privacy

Il codice del repository target viene letto dagli agenti e inviato al provider del modello configurato
in pi: è il normale funzionamento degli audit LLM. Nessun altro dato esce dalla macchina; review-dir e
report restano su disco locale (`$AARP_REVIEWS_DIR`, default `~/PI/aarp-reviews`).

## Uninstall

```bash
pi remove /percorso/pi-skill-aarp
```

Nessun file scritto dentro `~/.pi/agent`: si rimuove solo la dichiarazione del pacchetto. Le
review-dir già create restano dove sono.

## License

MIT — vedi [LICENSE](LICENSE).
