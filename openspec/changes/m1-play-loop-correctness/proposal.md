# Proposal: M1 Play-Loop Correctness (M1-1, M1-4)

## Intent

Two play-loop bugs in `RulesEngine.perform()` make every simulated or human
game incorrect. Any downstream work (M2 legal actions, M4 human play, M8 neural
training) inherits garbage state until these are fixed. This is the critical
path of the M1 milestone — **nothing else in M1 is trustworthy until the
play-loop mutates state correctly.**

## Scope

### In Scope

- **M1-1**: playing a card removes exactly ONE copy from the hand (not all
  copies sharing the id).
- **M1-4**: a player deploys at most ONE resource per turn.

### Out of Scope

- Tactic cost payment and timing windows → `m1-tactics-stronghold` (Phase 4).
- Building attachment to provinces → `m1-destinies-provinces` (Phase 3).
- Per-player metrics → `m1-effects-metrics` (Phase 5).
- Any balance/data change.

## Approach

Both bugs are localized to `RulesEngine.perform()` and `PlayerState`. No new
types, no data changes, no new public API surface.

- **M1-1** is more than a one-token fix: it replaces `Array.removeAll { $0 == id }`
  (deletes ALL copies) with `firstIndex(of: id)` + `remove(at:)` (deletes ONE
  copy) at four call sites, fusing the index resolution into the existing guard.
  The catalog lookup `state.card(for:)` validates only the global catalog, NOT
  hand membership; the hand index must therefore be resolved explicitly before
  any payment or effect is applied. This simultaneously fixes single-copy
  removal, hand-membership validation, and graceful rejection (no trap).
- **M1-4** adds an internal `Bool` turn flag to `PlayerState`, resets it at the
  start of `takeTurn`, and checks it in the `.playResource` case (rejecting the
  action with the existing "skip but keep turn" contract).

Strict TDD both ways: RED test with two copies / two resource deploys first.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `Sources/GameCore/RulesEngine.swift` | Modified | 4 sites: `removeAll`→`firstIndex(of:)`+`remove(at:)`; reset+check+set resource flag in `takeTurn`/`.playResource` |
| `Sources/GameCore/PlayerState.swift` | Modified | Add internal `var hasDeployedResourceThisTurn = false` (no public API change) |
| `Tests/GameCoreTests/PlayLoopTests.swift` | New | RED + regression tests for both behaviors |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Catalog id not in player's hand must not crash | High (gate RISK-1) | `firstIndex(of:)` returns nil → guard fails gracefully; no trap. RED test for catalog-but-not-in-hand (1.10a/b). Existing `state.card(for:)` checks the global catalog only, NOT hand membership — the index resolution is what closes RISK-1. |
| Other AI/turn code paths reset the flag at wrong time | Medium | Reset at exactly one place (first line of `takeTurn`, before `applyDestinyControlBonus`); add regression test for turn boundary |
| Existing snapshot/sim tests change behavior | Low (gate RISK-2: zero test blast radius) | Re-run `SimulationTests` determinism harness; no test asserts absolute numbers, so outputs shifting is acceptable. Selective revert of one commit is clean |

## Rollback Plan

Two atomic commits inside a single PR (see tasks.md 4.2):

1. `fix(core): M1-1 single-copy removal` (firstIndex + remove(at:) at 4 sites)
2. `fix(core): M1-4 one resource per turn` (flag + reset + guard + set)

Selective rollback: `git revert <commit>` for one fix only. Full rollback:
revert both commits in reverse order. No data migration, no on-disk format
change. The flag is a non-persisted runtime field.

## Dependencies

- None. This is the critical-path entry point of M1.

## Success Criteria

- [ ] RED tests for M1-1 and M1-4 fail before implementation, pass after.
- [ ] `swift build --build-tests` clean; full `swift test` suite green.
- [ ] `SimulationTests.testSameSeedProducesIdenticalResult` still passes
      (determinism preserved — fix must not introduce non-determinism).
- [ ] No new public API surface (field is internal to the engine).
