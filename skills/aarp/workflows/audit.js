// audit.js — Fasi 1-3 AARP: context mapping → 6 audit in parallelo → ROADMAP.
// Sandbox: nessun filesystem/shell; i child (agenti) fanno lettura/scrittura.
// args: { rd: <review-dir assoluta>, templatesDir: <radice pacchetto>, skip: [ "context","ux","sec","db","quality","infra","doc","roadmap" ] }
// Lancio: subagent({ workflow: "<skill>/workflows/audit.js", args: {...}, cwd: <source/snapshot> })

const rd = args.rd;
const templatesDir = args.templatesDir;
if (!rd) return { ok: false, error: "args.rd (review-dir) mancante" };
if (!templatesDir) return { ok: false, error: "args.templatesDir (radice pacchetto) mancante" };
const skip = new Set(args.skip || []);

function template(file) { return templatesDir + "/templates/" + file; }

// Mappa step: [key, agente, file report, file template]
const STEPS = [
  ["context", "context-mapper", "PROJECT_CONTEXT.md", "PROJECT_CONTEXT.template.md"],
  ["ux", "ux-ui-auditor", "AUDIT_UX_PERF.md", "AUDIT_UX_PERF.template.md"],
  ["sec", "security-auditor", "AUDIT_APPSEC.md", "AUDIT_APPSEC.template.md"],
  ["db", "db-auditor", "AUDIT_DATABASE.md", "AUDIT_DATABASE.template.md"],
  ["quality", "code-quality-auditor", "AUDIT_QUALITY.md", "AUDIT_QUALITY.template.md"],
  ["infra", "devops-auditor", "AUDIT_INFRA.md", "AUDIT_INFRA.template.md"],
  ["doc", "doc-coverage-auditor", "AUDIT_DOC_COVERAGE.md", "AUDIT_DOC_COVERAGE.template.md"],
  ["roadmap", "roadmap-director", "ROADMAP.md", "ROADMAP.template.md"],
];
function step(key) { return STEPS.find(function (s) { return s[0] === key; }); }

const context = step("context");
const ctx = skip.has("context")
  ? null
  : await runs.run("context", {
      label: "Mappa il contesto del progetto",
      agent: context[1],
      task: `Analizza lo snapshot del repository corrente e scrivi il blueprint in ${rd}/reports/${context[2]}. Usa il template obbligatorio ${template(context[3])} e rispetta il tuo contratto di output.`,
    });

const specs = STEPS.filter(function (s) { return s[0] !== "context" && s[0] !== "roadmap" && !skip.has(s[0]); });

const audits = await runs.all(specs.map(function (s) {
  return {
    key: s[0],
    label: "Audit " + s[0],
    agent: s[1],
    task: `Leggi il contesto in ${rd}/reports/PROJECT_CONTEXT.md (se assente, segnalalo come premessa). Analizza lo snapshot del repository corrente e scrivi il report in ${rd}/reports/${s[2]}, usando il template obbligatorio ${template(s[3])}.`,
  };
}));

let roadmap = null;
if (!skip.has("roadmap")) {
  const rm = step("roadmap");
  roadmap = await runs.run("roadmap", {
    label: "Sintesi roadmap P0/P1/P2",
    agent: rm[1],
    task: `Leggi i report in ${rd}/reports/ (PROJECT_CONTEXT.md e AUDIT_*.md) e produci ${rd}/reports/${rm[2]} usando il template obbligatorio ${template(rm[3])}: priorità P0/P1/P2, ID TASK-Pn-NN, campi Category / Target Location / Branch Name / Agent Assigned / Scope, e la tabella Status Tracking Checklist.`,
  });
}

return {
  context: ctx ? ctx.ok : "skipped",
  audits: audits.map(function (a, i) { return { key: specs[i][0], ok: a.ok }; }),
  roadmap: roadmap ? roadmap.ok : "skipped",
};
