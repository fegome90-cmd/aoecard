# Project documentation

> Index for the `docs/` tree. Strategic + tactical + historical, all in one place.
> For SDD artifacts (proposals, specs, designs, tasks, verify-reports), see
> [`openspec/`](../openspec/) — that tree has its own convention.

## Map

| Path | What | Type |
|---|---|---|
| [`ROADMAP.md`](ROADMAP.md) | M0–M10 strategic roadmap with verified status (2026-06-19). The entry point for "where is the project and where is it going". | Strategic, living |
| [`architecture/tech-debt.md`](architecture/tech-debt.md) | Deferred structural advisories (`resolve()` complexity, `writeRun` 8 params, `producesKind` tuple, `isReady` 3-writer AF-02 hazard). Each with risk + suggested approach. | Engineering reference |
| [`audits/`](audits/) | Dated audit reports — snapshots from specific review sessions. Append-only (don't edit old ones; add new dated files). | Historical, immutable |
| [`sprints/`](sprints/) | One subfolder per milestone sprint: backlog, task list, status. | Tactical, living |

## How the doc layers fit together

```
docs/ROADMAP.md                        ← "¿qué milestone sigue y por qué?"
    │
    ▼
docs/sprints/<milestone>/tasklist.md   ← "¿qué item ahora, con qué evidencia?"
    │
    ▼
openspec/changes/<change-name>/        ← "¿qué se decidió para ESTE cambio?"
    │  (proposal → spec → design → tasks → verify → archive)
    ▼
openspec/changes/archive/<date>-<chg>/ ← "¿qué se hizo y por qué?" (audit trail)
    │
    ▼
openspec/specs/<domain>/spec.md        ← "¿cuál es el contrato CANÓNICO actual?"
```

- **Strategy** (¿qué viene?): start at `ROADMAP.md`.
- **Tactics** (¿qué item ahora?): the `tasklist.md` of the active milestone.
- **Change decisions** (¿qué se decidió acá?): the `openspec/changes/<active>/` folder.
- **Canonical contracts** (¿cómo debe comportarse el sistema?): `openspec/specs/`.

## Conventions

- **Living docs** (ROADMAP, tasklists, tech-debt): edit in place; record major changes in their Changelog section.
- **Snapshots** (audits): never edit; supersede with a new dated file that references the prior one.
- **Archived SDD changes** (`openspec/changes/archive/`): never edit; they are the audit trail.
- **Canonical specs** (`openspec/specs/`): updated only via `sdd-archive` (delta merge from a completed change).
- **Cross-references**: prefer repo-relative paths (e.g. `docs/architecture/tech-debt.md`) so links survive moves within the tree.

## Current active sprint

`docs/sprints/m1-rules-fidelity/` — M1 Rules Fidelity. **Status**: 3/14 items done
(M1-1, M1-3, M1-4); 9 critical open; 1 instrumentation gap (M1-13).
See the tasklist for the dependency graph and the "do NOT resume card balance" gate.
