# Archive Report — m1-play-loop-correctness

**Change**: m1-play-loop-correctness
**Milestone**: M1 (Rules Fidelity, Phase 2)
**Archived**: 2026-06-18
**Archive path**: `openspec/changes/archive/2026-06-18-m1-play-loop-correctness/`
**Artifact store**: openspec

## SDD Cycle Complete

| Phase | Status | Evidence |
|-------|--------|----------|
| explore | done | `docs/sprint-m1-rules-fidelity/tasklist.md` (reality-check of 12 M1 items) |
| proposal | done | `proposal.md` (user-approved, reopened once for CRITICAL) |
| spec | done | `specs/play-loop/spec.md` (13 scenarios, RFC 2119) |
| design | done | `design.md` (D1-D4 decisions) |
| tasks | done | `tasks.md` (29 tasks, all [x] checked) |
| gate (spec) | conditional_pass | `gate-spec-report.md` (inline, structural audit clean) |
| gate (design) | pass_after_fix | `gate-design-report.md` (quorum 3/3, RISK-1 HIGH fixed) |
| gate (tasks) | pass_after_fix | `gate-tasks-report.md` (quorum 3/3) |
| judgment_day | approved | 3 rounds; user caught CRITICAL `removeFirst(where:)` nonexistent |
| apply | done | commits cb837be (M1-1), 82c6623 (M1-4), 415d349 (StrategyAI fix) |
| verify | passed | `verify-report.md` regenerated — 89 tests, 13/13 COMPLIANT |
| audits | pass | authority + cartographer + review + simplifier (2 rounds, glm-5.2) |
| ci | passed | GitHub Actions run 27801312041, macOS-15, 4m35s, success |
| sync | done | delta spec copied to `openspec/specs/play-loop/spec.md` (new domain) |
| archive | done | moved to `openspec/changes/archive/2026-06-18-m1-play-loop-correctness/` |

## Specs Synced

| Domain | Action | Details |
|--------|--------|---------|
| play-loop | Created | 13 scenarios across 2 requirements (single-copy removal; one resource per turn). Main spec `openspec/specs/play-loop/spec.md` did not exist before — delta spec IS the full spec, copied directly. |

## Archive Contents

- proposal.md ✅
- specs/play-loop/spec.md ✅ (the synced delta, kept as audit trail)
- design.md ✅ (D1-D4)
- tasks.md ✅ (29/29 [x])
- gate-spec-report.md ✅
- gate-design-report.md ✅
- gate-tasks-report.md ✅
- verify-report.md ✅ (regenerated 2026-06-18 after corrective)
- state.yaml ✅ (terminal: phase archive/completed)
- archive-report.md ✅ (this file)

## Commits on the change (chronological)

| Hash | Subject |
|------|---------|
| cb837be | fix(core): M1-1 single-copy removal |
| 82c6623 | fix(core): M1-4 one resource per turn |
| f656c1e | docs(openspec): SDD artifacts |
| db3695e | test(core): close M1 verify coverage gaps (S4/S5/S6) |
| 00dea36 | docs(openspec): verify-report + state (later superseded by 711d191) |
| 415d349 | fix(core): StrategyAI honors one-resource-per-turn + integration test |
| 711d191 | docs(openspec): regenerate verify report |
| b16bff9 | docs(openspec): cleanup + CI workflow |
| 9d8ef91 | style(openspec): reflow state.yaml comments |

All on `origin/main`. CI green on the final push.

## Source of Truth Updated

The following spec now reflects the new behavior:

- `openspec/specs/play-loop/spec.md` — canonical contract for play-loop semantics (single-copy removal, one resource per turn, hand-membership guard, no-trap invariants, observable-result determinism).

## Known gaps carried forward (non-blocking)

- **suite_wallclock_grew**: full suite went 140s → ~640s local / 4m35s CI. Correct behavior (turns no longer early-exit on 4-failure budget), not a regression. Track if simulation cost bottlenecks the M1-GATE (1000-game harness).
- **no_remote_ci for prior commits**: 5 implementation commits landed direct to main without PR/CI. CI workflow is now in place for future changes; this change's evidence is the run on the final push.
- **determinism invariant scoped**: spec now promises "identical observable results" not "byte-identical state" (UUID defaults still break full byte-equality). A future change introducing a deterministic `EntityID` could restore the stronger claim.

## SDD Cycle Complete

The change has been fully planned, implemented, verified, audited, published, synced, and archived. Ready for the next M1 phase.
