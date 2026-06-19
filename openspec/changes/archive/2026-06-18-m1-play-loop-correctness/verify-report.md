## Verification Report

**Change**: m1-play-loop-correctness
**Mode**: Strict TDD
**Date**: 2026-06-18
**Verifier**: el Gentleman (adversarial SDD verify, regenerated after corrective change)

> This report supersedes the prior (stale) report at commit `00dea36`, which
> predated both the S4/S5/S6 coverage closures (`db3e95e`) and the corrective
> StrategyAI fix (`415d349`). Every number below is taken from a fresh
> `swift build --build-tests` + `swift test` run on the final HEAD, not from
> memory or the prior report.

### Summary verdict

**PASS** — 13/13 spec scenarios COMPLIANT, 0 PARTIAL, 0 FAILING. Full suite
**89 tests, 0 failures**. Determinism preserved
(`SimulationTests.testSameSeedProducesIdenticalResult` passed).

The prior dictamen finding is closed: M1-4's one-resource-per-turn flag was
correct in `RulesEngine.perform()` but the AI's legal-action producer
(`StrategyAI.legalActions()`) did not know about it, so the AI kept choosing
resources `perform()` rejected and exhausted the `consecutiveFailures < 4`
budget, ending turns early and distorting simulations. The corrective change
(`415d349`) makes the producer honor the flag, restoring agreement between
producer and executor. The integration test `testAIContinuesWithUnitAfterFirstResource`
was RED before the fix (unit never reached) and GREEN after.

### Completeness

| Metric | Value |
|--------|-------|
| Code/test commits verified | 4 — `cb837be` (M1-1), `82c6623` (M1-4), `db3e95e` (S4/S5/S6), `415d349` (corrective) |
| Source files changed | 3 — `RulesEngine.swift`, `PlayerState.swift`, `StrategyAI.swift` |
| Test files changed | 1 — `PlayLoopTests.swift` (15 tests across 2 classes) |
| Spec scenarios | 13 |
| Design decisions | D1–D4 (original) + D5 (corrective: producer mirrors executor) |
| Tasks phases | 3 (Phase 1 M1-1, Phase 2 M1-4, Phase 3 regression) |

### Build & tests execution (final HEAD)

| Check | Result |
|-------|--------|
| `swift build --build-tests` | ✅ Exit 0 — `Build complete!` |
| `swift test` (full suite) | ✅ **89 tests, 0 failures** (exit 0, ~640s) |
| `swift test --filter PlayLoop` | ✅ **15 tests, 0 failures** (10 `PlayLoopTests` + 5 `PlayLoopResourceSlotTests`) |
| `SimulationTests.testSameSeedProducesIdenticalResult` | ✅ Passed (0.209s) — determinism preserved |
| Failure/error lines in full log | 0 |

Execution evidence (verbatim from `swift test`):

```
Test Suite 'PlayLoopTests' passed ... Executed 10 tests, with 0 failures
Test Suite 'PlayLoopResourceSlotTests' passed ... Executed 5 tests, with 0 failures
Test Suite 'SimulationTests' passed ... Executed 9 tests, with 0 failures
Test Suite 'All tests' passed ... Executed 89 tests, with 0 failures (639.595 seconds)
```

> Coverage was **not** re-collected in this corrective pass (verify scope was
> build + full test re-execution, per the corrective plan). The prior report's
> line-coverage figures (~96.8% `RulesEngine`, ~95.0% `PlayerState`) are not
> restated here to avoid carrying un-reproduced numbers; the new integration
> test additionally exercises the `StrategyAI.choose` → `perform` path end-to-end.

### TDD compliance

Strict TDD is active (`openspec/config.yaml`: `strict_tdd: true`). The
corrective item was driven RED-first: the integration test below was written
and confirmed failing **before** the `StrategyAI` fix, then turned GREEN by
the fix. All pre-existing tests remained green throughout (no revert of M1-1
or M1-4).

| Area | Test | Code fix | RED→GREEN evidence |
|------|------|----------|-------------------|
| M1-1 removal | `testPlayResourceRemovesExactlyOneCopy` | `firstIndex` + `remove(at:)` | Prior commits; still green |
| M1-1 (tactic) | `testPlayTacticRemovesExactlyOneCopy` | index resolved before effects loop | Prior commits; still green |
| M1-4 flag | `testSecondResourceSameTurnIsRejected` | flag + reset + guard in `perform` | Prior commit `82c6623` |
| **Corrective** | **`testAIContinuesWithUnitAfterFirstResource`** | **`legalActions()` `.resource` guards on flag** | **RED: `XCTAssertTrue failed - AI must continue to the unit after the first resource (turn not ended early)` → GREEN after `415d349`** |

### Test layer distribution

| Layer | Count | Tests |
|-------|-------|-------|
| Unit | 14 | Direct `perform`/`takeTurnForTest` calls asserting state mutations. |
| Integration | 1 | `testAIContinuesWithUnitAfterFirstResource` drives a full `takeTurn` through `StrategyAI.choose` → `perform`, proving producer/executor agreement and that the turn does not end early. |

### Spec compliance matrix

| # | Requirement | Scenario | Test(s) | Result |
|---|-------------|----------|---------|--------|
| S1 | Single-copy removal | Two identical resource copies | `testPlayResourceRemovesExactlyOneCopy` | ✅ COMPLIANT |
| S2 | Single-copy removal | Two identical unit copies | `testPlayUnitRemovesExactlyOneCopy` | ✅ COMPLIANT |
| S3 | Single-copy removal | Two identical tactic copies | `testPlayTacticRemovesExactlyOneCopy` | ✅ COMPLIANT |
| S4 | Single-copy removal | Single-copy hand is unaffected in count | `testSingleCopyHandEmptiesToZero` | ✅ COMPLIANT (closed by `db3e95e`) |
| S5 | Single-copy removal | Remaining copy after a play is still playable | `testRemainingCopyAfterPlayIsStillPlayable` | ✅ COMPLIANT (closed by `db3e95e`; Judgment Day F11) |
| S6 | Single-copy removal | Empty empire hand rejects ALL play actions, no crash | `testEmptyHandRejectsAllPlayActions` | ✅ COMPLIANT (closed by `db3e95e`) |
| S7 | Single-copy removal | Payment failure removes nothing | `testPaymentFailureRemovesNothing` | ✅ COMPLIANT |
| S8 | Single-copy removal | Valid catalog id not in hand rejected, no crash | `testPlayResourceNotInHandIsRejected` + `testPlayTacticNotInHandIsRejectedNoEffects` | ✅ COMPLIANT |
| S9 | Single-copy removal | Valid catalog tactic not in hand, no effects fired | `testPlayTacticNotInHandIsRejectedNoEffects` | ✅ COMPLIANT |
| S10 | One resource per turn | First resource in a turn succeeds | `testFirstResourceInTurnSucceeds` | ✅ COMPLIANT |
| S11 | One resource per turn | Second resource in the same turn is rejected | `testSecondResourceSameTurnIsRejected` + **`testAIContinuesWithUnitAfterFirstResource`** (producer side) | ✅ COMPLIANT |
| S12 | One resource per turn | Flag resets at the start of each turn | `testFlagResetsEachTurn` | ✅ COMPLIANT |
| S13 | One resource per turn | Rejected resource does not consume the slot | `testFailedPaymentDoesNotConsumeSlot` | ✅ COMPLIANT |

**Compliance summary**: **13/13 COMPLIANT**, 0 PARTIAL, 0 FAILING, 0 UNTESTED.

The new integration test (`testAIContinuesWithUnitAfterFirstResource`) maps to
**S11** ("second resource in the same turn is rejected") and to the spirit of
the "at most one resource per turn" requirement: it proves the rejection is
honored by the *AI producer*, not just by `perform()`, so the simulator no
longer ends turns early on rejected resources. This is the scenario the prior
verify could not see because it only tested `perform()` in isolation.

### Coherence (design)

| Decision | Followed? | Notes |
|----------|-----------|-------|
| D1 — `firstIndex(of:)` + `remove(at:)` | ✅ Yes | All 4 play sites; `removeAll` gone; tactic index resolved before effects. Not reverted. |
| D2 — Transient turn flag, not persisted | ✅ Yes | `hasDeployedResourceThisTurn` is internal `var`, default `false`, no `CodingKeys`. |
| D3 — Flag does not touch `isReady` | ✅ Yes | Orthogonal to `ResourceInPlay.isReady` / `readyAll()`. |
| D4 — Reset at exactly one place (start of `takeTurn`) | ✅ Yes | First line of `takeTurn`, before `applyDestinyControlBonus`. |
| **D5 — Producer mirrors executor (corrective)** | ✅ Yes | `legalActions()` `.resource` case guards on `!player.hasDeployedResourceThisTurn`, exactly matching `perform()`'s guard. One truth, two call sites. |

Rejected alternatives NOT implemented: confirmed. No `removeFirst(where:)`,
no persisted flag, no `isReady` coupling, no extra reset points, no
non-determinism introduced by the producer filter (it reads an existing
boolean flag; no UUID/wall-clock/sort/shuffle).

### Determinism invariants (load-bearing)

- ✅ The producer filter is a pure read of `hasDeployedResourceThisTurn`, itself
  a pure function of turn boundaries. No new ordering or RNG use introduced.
- ✅ Card removal order unchanged (`firstIndex` + `remove(at:)` on seed-derived
  hand order).
- ✅ `SimulationTests.testSameSeedProducesIdenticalResult` PASSED on final HEAD.
  Same seed + same action sequence reproduces byte-identical state and log.

### Assertion quality audit (Step 5f — mandatory, on final test file)

All 15 tests audited. No tautologies, no `expect(true).toBe(true)`, no
assertions without production-code calls.

| Test | Key assertions | Quality |
|------|---------------|---------|
| `testPlayResourceRemovesExactlyOneCopy` | `performed` + hand == `["res_a"]` | ✅ Real |
| `testPlayUnitRemovesExactlyOneCopy` | `performed` + hand == `["unit_a"]` | ✅ Real |
| `testPlayBuildingRemovesExactlyOneCopy` | `performed` + hand == `["bldg_a"]` | ✅ Real |
| `testPlayTacticRemovesExactlyOneCopy` | `performed` + tacticsHand == `["tac_a"]` | ✅ Real |
| `testPlayResourceNotInHandIsRejected` | `!performed` + `continueTurn` | ✅ Real |
| `testPlayTacticNotInHandIsRejectedNoEffects` | `!performed` + `continueTurn` + `!isReady` | ✅ Real (3 assertions pin rejection AND no side effects) |
| `testPaymentFailureRemovesNothing` | `!performed` + hand unchanged | ✅ Real |
| `testSecondResourceSameTurnIsRejected` | `performed`/`!performed`/`continueTurn` + hand contains `res_b` **+ no-tap/no-waste** | ✅ Real (strengthened: rejected resource performs zero side effects) |
| `testFirstResourceInTurnSucceeds` | `performed` + flag set | ✅ Real |
| `testFlagResetsEachTurn` | flag false→deploy→flag true→turn→flag false→deploy→performed | ✅ Real (multi-step reset cycle) |
| `testFailedPaymentDoesNotConsumeSlot` | 3-step sequence, `performed`/flag/hand **+ no-tap/no-waste on rejected retry** | ✅ Real (strengthened on the slot-consumed retry) |
| `testSingleCopyHandEmptiesToZero` | `performed` + hand empty | ✅ Real (S4) |
| `testRemainingCopyAfterPlayIsStillPlayable` | two sequential plays, hand → `["res_a"]` → empty | ✅ Real (S5 / F11) |
| `testEmptyHandRejectsAllPlayActions` | all 4 play types rejected + `continueTurn` + no crash | ✅ Real (S6) |
| `testAIContinuesWithUnitAfterFirstResource` | exactly 1 resource deployed + unit deployed + flag set | ✅ Real (integration; the distortion-fix proof) |

### Issues found

**CRITICAL**: *(none)*

**WARNING**: *(none — all prior PARTIAL gaps (S4/S5/S6) closed by `db3e95e`;
the S11 producer-side gap closed by `415d349`)*

**SUGGESTION**:

1. Task checkboxes in `tasks.md` remain bookkeeping-only; out of scope for this
   corrective change (orchestrator handles `tasks.md`/`design.md` cleanup
   separately).
2. Test-class split (`PlayLoopTests` + `PlayLoopResourceSlotTests` with a
   `fileprivate PlayLoopTestSupport` factory) was introduced to clear the
   `type_body_length` (350) structural limit after the integration test pushed
   the single class over. Behavior is unchanged; all helpers are shared.

### Verdict

**PASS** — 13/13 COMPLIANT, full suite **89 tests / 0 failures**, determinism
preserved. The corrective change (`415d349`) closes the last open gap: the
one-resource-per-turn flag is now enforced by both the legal-action producer
and the action executor, so simulations no longer end turns early on rejected
resources. No CRITICAL issues, no failing tests, no partial scenarios remain.
