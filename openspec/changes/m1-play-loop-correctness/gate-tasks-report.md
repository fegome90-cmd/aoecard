# SDD Gate Report — m1-play-loop-correctness / tasks phase (QUORUM)

**Gate target**: `openspec/changes/m1-play-loop-correctness/tasks.md`
**Run**: 2026-06-17 · **Skill**: sdd-gate-skill v1.3.0 · **Mode**: QUORUM (3 agents, paid `zai/glm-5-turbo`)
**Wall clock**: 105s

## Phase 2 — Agent dispatch (3/3 completed, quorum met)

Three independent `pi --mode json -p` headless agents. Outputs:
`/tmp/gt-{struct,design,risk}-out.log`. Cleaned up after aggregation.

## Phase 3 — Aggregation (deduplicated, evidence verified)

| Sev | ID | Lens | Title | Verified? |
|-----|----|------|-------|-----------|
| **Medium** | RISK-T3 | risk | Single commit bundles 2 independent fixes → breaks revert granularity | ✅ valid — design itself says they're code-independent |
| Medium | DES-1 / STRUCT-T1 | design+structure | Tactic catalog-but-not-in-hand (spec S7) has NO RED test — only resource S6 is covered (task 1.10) | ✅ valid gap |
| Medium | RISK-T2 | risk | Task 2.2 doesn't pin the guard ORDER (contains → flag → payment → commit → removeFirst → deploy → set flag) — relies on 2.6 to discover wrong order | ✅ valid — ambiguity real, TDD catches but task should be explicit |
| Low | DES-2 | design | Task 2.2 omits the doc comment (transient / no-serialize / no-AF-02) from design Interfaces section | ✅ valid — comment is the defense against M4 drift |
| Low (wording) | RISK-T1 | risk | D4 says "for the controller only" but both players get takeTurn each round → misleading (NOT a bug) | ✅ verified — code resets both flags correctly; D4 wording should amend |
| Info | STRUCT-T2 | structure | STRUCT-6 "throws"→"traps" already fixed in design; no task pins it | ✅ resolved |
| Info | STRUCT-T3 | structure | All gate findings (RISK-1, DESIGN-D4, RISK-2/3/4) reflected in tasks | ✅ |
| Info | STRUCT-T4 | structure | TDD discipline strict — every GREEN has preceding RED | ✅ |
| Info | STRUCT-T5 | structure | Atomicity + hierarchy conform to config rules.tasks | ✅ |
| Info | STRUCT-T6 | structure | Build/test commands concrete and existing | ✅ |
| Info | STRUCT-T7 | structure | DoD present and measurable | ✅ |
| Info | DES-3 | design | Tasks 1.10/2.3/2.4/2.5 are regression pins (PASS immediately, not strict RED) — correct practice | ✅ |
| Info | RISK-T4 | risk | Task 1.10 ordering claim verified: guard IS evaluated before removeFirst | ✅ |
| Info | RISK-T5 | risk | Determinism test compares r1 vs r2 (not hardcoded) — shift is safe, rollback clean | ✅ |

## The findings that require action

Three Medium findings need small amendments to tasks.md (and one to design D4).
None are Critical/High — the gate is REVIEW, not BLOCK. All fixes are
document/spec edits, NOT code changes (apply phase hasn't started).

### RISK-T3 (Medium) — split into 2 commits

The change bundles two **code-independent** fixes (design.md says so explicitly)
into one commit. If M1-4 regresses, reverting also yanks M1-1. Recommendation:
**2 commits** for `git revert` granularity:

- `fix(core): M1-1 single-copy removal`
- `fix(core): M1-4 one resource per turn`
(Still one PR per the `single-pr-default` preflight — just 2 commits inside it.)

### DES-1 / STRUCT-T1 (Medium) — add the missing tactic RED test

Spec scenario S7 ("valid catalog tactic not in tactics hand → rejected without
crashing") has no RED task. Only S6 (resource) is covered by task 1.10. The
`.playTactic` guard lands in task 1.9 but no test pins it. Without this, RISK-1
stays silently open on the tactic path. **Fix**: split task 1.10 into 1.10a
(resource) + 1.10b (tactic).

### RISK-T2 (Medium) — pin the guard order in task 2.2

Task 2.2 says "flag check at top of case" + "set flag after deploy" but does
NOT specify the relative order vs the hand-membership guard (from 1.3) and the
payment guard. Task 2.6 "confirms" the order — meaning it discovers wrong order
rather than preventing it. TDD catches it (test 2.5 fails), but the task should
be explicit. **Fix**: add to 2.2 the exact order:
`contains → flag check → payment → commit → removeFirst → deploy → set flag → write back`.

### DES-2 (Low) + RISK-T1 (Low, wording)

- DES-2: add the doc comment to task 2.2 (transient / no-serialize / no-AF-02).
- RISK-T1: amend design D4 wording from "for the controller only" to
  "at the start of each player's takeTurn — both players are processed each
  round via the round loop (play() L100-115), so both flags reset naturally."

## Phase 4 — Gate decision

| Metric | Value |
|--------|-------|
| Findings Reported / Discarded | 14 / 0 |
| Verification Rate | 100% |
| Agents Completed | 3 / 3 |
| Quorum | 3 / 3 valid |
| **Gate** | **REVIEW** |
| Critical/High | 0 / 0 |

### Matrix application

- critical = 0, high = 0 → no auto-BLOCK, no REVIEW-by-severity
- 2 agents PASS + 1 REVIEW → tie-break REVIEW > PASS → **REVIEW**
- Quorum authoritative (3/3)

### Recommended path

REVIEW → fix the 3 Medium findings in tasks.md (and the D4 wording in
design.md), then proceed to `apply`. All fixes are doc edits; no re-design.
Estimated 10 min of editing.

## Tool evidence used

- 3× `pi --mode json -p --model zai/glm-5-turbo -nc @/tmp/gate-tasks-*-prompt.txt`
- orchestrator re-verification of RISK-T1 against `RulesEngine.swift:100-124`
  (round loop calls takeTurn for both playerIdx values)
- previous Phase 1.5 structural audit + design gate report (carried forward)
