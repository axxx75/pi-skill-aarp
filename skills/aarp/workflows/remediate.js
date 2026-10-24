// remediate.js — Fase 4 AARP: per ogni task approvato, catena Developer → QA → Code Review.
// Sandbox: nessun filesystem/shell; i child (agenti) fanno lettura/scrittura.
// Un writer per worktree: i task hanno worktree distinti e la catena è sequenziale.
// args: { templatesDir: <radice pacchetto>, tasks: [ { id, title, branch, worktree, scope } ] }
// Lancio: subagent({ workflow: "<skill>/workflows/remediate.js", args: {...}, cwd: <review-dir o repo base> })

const tasks = args.tasks || [];
const templatesDir = args.templatesDir;
if (!tasks.length) return { ok: false, error: "args.tasks vuoto" };
if (!templatesDir) return { ok: false, error: "args.templatesDir (radice pacchetto) mancante" };

function template(file) { return templatesDir + "/templates/" + file; }

// Mappa step: [key, agente, file report, file template]
const STEPS = [
  ["dev", "developer", null, null],
  ["qa", "qa-test", "TEST_REPORT.md", "TEST_REPORT.template.md"],
  ["review", "code-reviewer", "REVIEW_REPORT.md", "REVIEW_REPORT.template.md"],
];
function step(key) { return STEPS.find(function (s) { return s[0] === key; }); }

function brief(r) {
  if (!r) return null;
  return { ok: r.ok, summary: r.summary || r.text || r.output || null };
}

const results = [];
for (const t of tasks) {
  if (!t.worktree) {
    results.push({ id: t.id, error: "worktree mancante" });
    continue;
  }

  const devStep = step("dev");
  const dev = await runs.run(t.id + "-dev", {
    label: t.id + " - Developer",
    agent: devStep[1],
    cwd: t.worktree,
    task: `Risolvi il task ${t.id} (${t.title}) sul branch ${t.branch} già pronto nel worktree. Scope & Remediation: ${t.scope}. Rispetta il tuo contratto: implementa, testa in locale e committa sul branch.`,
  });

  const qaStep = step("qa");
  const qa = await runs.run(t.id + "-qa", {
    label: t.id + " - QA",
    agent: qaStep[1],
    cwd: t.worktree,
    task: `Verifica il task ${t.id} (${t.title}) sul branch ${t.branch}. Esegui i test e valida il criterio di accettazione dello scope: ${t.scope}. Riporta esito e comandi eseguiti in ${t.worktree}/${qaStep[2]}, usando il template obbligatorio ${template(qaStep[3])}.`,
  });

  const revStep = step("review");
  const rev = await runs.run(t.id + "-review", {
    label: t.id + " - Code Review",
    agent: revStep[1],
    cwd: t.worktree,
    task: `Rivedi il diff del branch ${t.branch} per il task ${t.id} (${t.title}). Emetti un unico verdetto APPROVED o REJECTED con motivazioni e fix richiesti. Scope atteso: ${t.scope}. Scrivi la review in ${t.worktree}/${revStep[2]}, usando il template obbligatorio ${template(revStep[3])}.`,
  });

  results.push({ id: t.id, dev: dev.ok, qa: qa.ok, review: brief(rev) });
}

return { results: results };
