# SDD Gate Report — m1-play-loop-correctness / spec phase

**Gate target**: `openspec/changes/m1-play-loop-correctness/specs/play-loop/spec.md`
**Run**: 2026-06-17 · **Skill**: sdd-gate-skill v1.3.0 · **Mode**: degraded (single-agent)

## Phase 0 — Config validation ✓

| Check | Value | Pass |
|-------|-------|------|
| change-name | `m1-play-loop-correctness` | ✓ |
| artifact store | `openspec` (`config.yaml`) | ✓ |
| spec size | 115 lines / 4890 chars (< 2000 / < 50000) | ✓ |

## Phase 0.5 — Injection defense

Scanned spec for injection patterns. **One substring match** at `:66`
(`"…the turn MUST continue (same contract as a failed payment)"`) —
this is a **false positive**: the `-e "act as"` pattern matched "act as"
inside "contr**act as**". Not an injection. **No action. Spec content is
trusted (authored this session).**

## Phase 1 — Artifact retrieval ✓

| Artifact | Status |
|----------|--------|
| proposal.md | ✓ present |
| specs/play-loop/spec.md | ✓ present (target) |
| design.md | not yet (next phase — allowed) |
| tasks.md | not yet (allowed) |

## Phase 1.5 — Structural audit (MANDATORY: change mutates game state)

Trigger met: change touches `empireHand`, `tacticsHand`, `resources[]`,
`PlayerState` — authoritative game-state mutation paths.

### Authority summary

| State field | Remove authority | Add authority | Competing writers? |
|---|---|---|---|
| `empireHand` | `RulesEngine.perform()` (3 sites: `:211`, `:227`, `:244`) | `PlayerState.drawEmpire()` (`:185`) | **No** — single remove path |
| `tacticsHand` | `RulesEngine.perform()` (1 site: `:279`) | `PlayerState.drawTactics()` (`:191`) | **No** — single remove path |
| `resources[]` | n/a (deployment adds) | `perform()` `.playResource` (`:213`) | **Adjacent risk**: `isReady` has known 3-writer fragility (AF-02, `docs/tech-debt.md`). The new flag does NOT add a competing writer to `isReady`. |

**Authority verdict**: `RulesEngine.perform()` is the **sole authority** for
hand-card removal. The fix is LOCAL — no SSOT ambiguity, no double-writer on
the hands. The new M1-4 flag is a new single-writer field (reset in `takeTurn`,
set in `.playResource`).

### Connectivity summary (grep-based — see freshness note)

- `perform()` callers: `takeTurn` (`:135`, production) + 4 test sites (all
  `assaultProvince`/`incursion` — **none exercise play-card removal**).
- Blast radius: `RulesEngine.perform()`, `PlayerState` struct, new tests.
  No callers outside the engine.

### Freshness note

**Trifecta graph: 0 nodes / 0 edges — STALE/EMPTY.** Trifecta does not index
Swift (Python-focused). Per skill error handling, connectivity claims above are
**grep-based, not graph-based** → confidence downgraded, disclosed honestly.
Reindexing will not help for Swift.

## Phase 2 — Agent dispatch (DEGRADED: 1 agent inline, no quorum)

Full skill requires 3 parallel agents (`sdd-structure`, `sdd-design`,
`sdd-risk`) for quorum (≥2). I ran the three lenses inline as a single agent.
**Per the gate matrix, <2 agents = INCONCLUSIVE on the dispatch portion.**
The structural audit (Phase 1.5) is authoritative on its own and does not
require quorum.

### Inline lens findings

**sdd-structure lens**

- **F1 (LOW) — Scenario coverage gap on Requirement 1.**
  The prose says removal "applies to all play actions: resource, unit,
  building, technology, special, and tactic", but scenarios only cover
  resource, unit, tactic. Building/technology/special share one code path
  (`RulesEngine.swift:244`, single `case` for all three), so coverage is
  implicit — but a strict reader wants either an explicit scenario or a note.
  **Evidence**: spec `:28-30` (prose) vs scenarios; code `:244` shared case.

- **F2 (INFO) — Zero existing coverage of the play-remove path.**
  All 4 existing `perform()` test calls are `assaultProvince`/`incursion`. No
  test exercises `.playResource`/`.playUnit`/`.playTactic` removal. This
  confirms the proposal's success criterion ("RED fails before") is correct
  and necessary. Not a blocker — it is WHY tests are added.
  **Evidence**: grep `\.perform\(` in Tests/.

**sdd-design lens**

- **F3 (MEDIUM) — M1-4 flag persistence/serialization not specified.**
  The proposal calls it a "non-persisted runtime field"; the spec's Determinism
  Invariants say it's "a pure function of turn boundaries". But `PlayerState`
  is a public struct. Two open questions for the design phase:
  (a) If `PlayerState` is `Codable` for M4 save/load, the flag needs a
  `CodingKey` decision (persist vs re-derive on load).
  (b) For M3 replay (seed + actions reproduce state), a transient flag derived
  from turn boundaries is correct — but this should be stated, not assumed.
  **Evidence**: spec `:108-110` (invariants); proposal rollback section.

**sdd-risk lens**

- **F4 (LOW) — Proximity to AF-02 (known `isReady` 3-writer fragility).**
  M1-4 deploys into `resources[]`, the same array family that has the known
  `isReady` coordination hazard (`docs/tech-debt.md`). The new flag does not
  touch `isReady`, but the design MUST NOT introduce a 4th writer to `isReady`
  or couple the new flag's lifecycle to the tap/untap invariant.
  **Evidence**: `docs/tech-debt.md` AF-02; `PlayerState.readyAll`.

## Phase 3 — Aggregation & gate decision

### Findings by severity

| Severity | Count | IDs |
|----------|-------|-----|
| Critical | 0 | — |
| High | 0 | — |
| Medium | 1 | F3 |
| Low | 2 | F1, F4 |
| Info | 1 | F2 |

### Gate matrix application

- critical = 0 → no auto-BLOCK
- high = 0 → no REVIEW threshold breach
- **Quorum NOT met (1/3 agents, degraded)** → dispatch verdict = **INCONCLUSIVE**
- Structural audit (authoritative, no quorum needed): no BLOCK/authority
  ambiguity found.

## Phase 4 — Report

| Metric | Value |
|--------|-------|
| Findings Reported / Discarded | 4 / 0 (1 false positive in 0.5 discarded) |
| Verification Rate | 100% (all cite code/spec evidence) |
| Agents Completed | 1 / 3 (degraded inline) |
| Quorum | 0 / 3 valid → INCONCLUSIVE on dispatch |
| **Gate** | **INCONCLUSIVE (degraded)** → CONDITIONAL PASS |
| Structural Audit Run | Yes |
| Trifecta Reindex Performed | No (Swift unsupported; grep-based) |

### Recommended gate interpretation

**CONDITIONAL PASS — proceed to design with F1 and F3 resolved there.**

Rationale: the structural audit (mandatory, authoritative) found **no authority
ambiguity and no competing writers** — the strongest signal for a state-mutation
change. The one MEDIUM (F3, flag serialization) is a design-phase question, not
a spec defect. The two LOW findings are coverage/clarity notes.

**To convert INCONCLUSIVE → PASS with real quorum**, spawn the 3 agents
(`sdd-structure` / `sdd-design` / `sdd-risk`) via TaskExecute/tmux-fork. For a
2-bug, 4.9 KB spec this is optional ceremony; the structural audit already
carries the decision.

### Actions before design phase

1. **(spec, optional)** F1: add a note under Requirement 1 that
   building/technology/special share the `:244` code path and are covered by
   the unit/resource scenarios, OR add one explicit scenario.
2. **(design, required)** F3: decide flag persistence — transient (derive from
   turn boundaries, no CodingKey) vs stored (add CodingKey for future M4
   save/load). State the decision in the design doc.
3. **(design, required)** F4: affirm the new flag does NOT touch the `isReady`
   tap/untap invariant and does not become a 4th writer.

### Tool evidence used

- `rg` on `Sources/` for writer/caller analysis (substitute for Trifecta graph)
- `rg` injection scan on spec artifact
- `trifecta graph overview` (returned empty for Swift — disclosed)
- `docs/tech-debt.md` AF-02 reference
- spec + proposal artifact reads
