# SDD Gate Report — m1-play-loop-correctness / design phase (QUORUM)

**Gate target**: `openspec/changes/m1-play-loop-correctness/design.md`
**Run**: 2026-06-17 · **Skill**: sdd-gate-skill v1.3.0 · **Mode**: QUORUM (3 agents via tmux-fork, paid `zai/glm-5-turbo`)
**Wall clock**: 81s

## Phase 2 — Agent dispatch (3/3 completed, quorum met)

Three independent `pi --mode json -p` headless agents, fresh context each (`-nc`),
paid model `zai/glm-5-turbo` (P11: paid mandatory for 2+ concurrent). Each got
its lens mandate + the authoritative structural-audit input. Outputs in
`/tmp/gate-{structure,design,risk}-out.log`.

## Phase 3 — Aggregation

### Findings by severity (deduplicated, evidence verified)

| Sev | ID | Lens | Title | Verified? |
|-----|----|------|-------|-----------|
| **HIGH** | RISK-1 | risk | `removeFirst` guard is catalog-only, NOT hand-membership → fatal crash on missing-from-hand id | ✅ VERIFIED against code |
| Medium | STRUCT-2 | structure | Testing table lists 4 M1-1 scenarios; spec has 5 (payment-failure missing) | ✅ |
| Low | STRUCT-3 | structure | D3 "Alternatives: none" is stylistically weak | ✅ |
| Info | STRUCT-4 | structure | All design sections present/well-formed | ✅ |
| Info | STRUCT-5 | structure | PlayerState confirmed NOT Codable → D2 holds | ✅ |
| Info | STRUCT-6 | structure | "throws" should be "traps" in D1 (terminology) | ✅ |
| Info | DESIGN-1 | design | Scenario 8 traces cleanly through data flow | ✅ |
| Info | DESIGN-2 | design | All 9 spec scenarios covered by testing strategy | ✅ |
| Info | DESIGN-D4 | design | Reset ordering: must be first line of takeTurn, before applyDestinyControlBonus | ✅ |
| Low | RISK-2 | risk | Masking risk has ZERO test blast radius (no tests assert absolute numbers) | ✅ |
| Low | RISK-3 | risk | Flag reset timing sound across all turn boundaries | ✅ |
| Info | RISK-4 | risk | No new non-determinism introduced | ✅ |

### The one that matters — RISK-1 (HIGH)

**The finding (verified against code)**: every play site guards with
`state.card(for: id)`, which looks up the **global catalog** (`cardsById`), NOT
the player's hand. My design D1 claimed "every call site is guarded by a lookup
that guarantees the id is present" — **factually incorrect**. The guard
guarantees the catalog id, not hand membership.

- With `removeAll`: missing-from-hand id = silent no-op (buggy but non-crashing).
- With `removeFirst(where:)`: missing-from-hand id = **fatal precondition trap**
  (`fatalError`, not a throw — STRUCT-6 corrected the terminology too).
- `perform` is `internal` (not private) for test access → any test or future
  code calling `perform` with a valid-catalog-but-not-in-hand id crashes fatally.
- `.playTactic` is the thinnest site (catalog guard only, no payment gate).

**Evidence**: `Sources/GameCore/StrategyAI.swift:120` (`card(for:) = cardsById[id]`);
`GameState.swift:38` (`public let cardsById`); `RulesEngine.swift:194`
(`func perform` — internal); the 4 guard sites at `:201, 217, 234, 270`.

This is exactly why the quorum spawn was worth it: my inline pass rated this
"Low" with a wrong rationale. The independent RISK lens caught the real
severity and the factual error in my design.

## Phase 4 — Gate decision

| Metric | Value |
|--------|-------|
| Findings Reported / Discarded | 12 / 0 |
| Verification Rate | 100% (all cite code/spec; HIGH re-verified by orchestrator) |
| Agents Completed | 3 / 3 |
| Quorum | 3 / 3 valid |
| **Gate** | **REVIEW** |
| Structural Audit Run | Yes (Phase 1.5, spec gate) |
| Trifecta Reindex Performed | No (Swift unsupported) |

### Matrix application

- critical = 0 → no auto-BLOCK
- high = 1 (RISK-1) → **REVIEW** (high>0 threshold met; high>2 not met)
- Quorum 3/3 → verdict is authoritative, not INCONCLUSIVE
- 2 agents voted PASS, 1 voted REVIEW → per tie-break, REVIEW > PASS

## Recommended actions before tasks phase

RISK-1 (HIGH, required): amend D1 and the proposal risk table. Two valid fixes:

- **(preferred)** Add `player.empireHand.contains(id)` (or `tacticsHand.contains(id)`
  for tactics) to each of the 4 guard clauses. Cheap, explicit, keeps `removeFirst`.
- (alternative) Replace `removeFirst(where:)` with `firstIndex(where:)` +
  `remove(at:)` that returns gracefully on not-found. More defensive but more
  verbose.

The spec is also affected: add a scenario "card id in catalog but not in hand
→ action not performed, no crash" under Requirement 1.

Medium/LOW/Info findings: fold into tasks as polish (scenario 5 in testing
table, "traps" terminology, D3 alternative wording, reset-ordering note).

## Tool evidence used

- 3× `pi --mode json -p --model zai/glm-5-turbo -nc @/tmp/gate-design-*-prompt.txt`
- orchestrator re-verification of RISK-1 against
  `Sources/GameCore/{StrategyAI,GameState,RulesEngine}.swift`
- previous Phase 1.5 structural audit (carried forward)
