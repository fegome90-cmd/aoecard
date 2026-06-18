## Verification Report

**Change**: m1-play-loop-correctness
**Mode**: Strict TDD
**Date**: 2026-06-18
**Verifier**: el Gentleman (adversarial SDD verify)

### Completeness

| Metric | Value |
|--------|-------|
| Commits verified | 2 (cb837be, 82c6623) |
| Source files changed | 2 (RulesEngine.swift, PlayerState.swift) |
| Test files created | 1 (PlayLoopTests.swift — 11 tests) |
| Spec scenarios | 13 |
| Design decisions | 4 (D1–D4) |
| Tasks phases | 3 (Phase 1 M1-1, Phase 2 M1-4, Phase 3 regression) |

### Build & Tests Execution

| Check | Result |
|-------|--------|
| `swift build --build-tests` | ✅ Exit 0, Build complete! |
| `swift test` (full suite) | ✅ **85 tests, 0 failures** (exit 0) |
| `swift test --filter PlayLoopTests` | ✅ **11 tests, 0 failures** (exit 0) |
| `SimulationTests.testSameSeedProducesIdenticalResult` | ✅ Passed (determinism preserved) |
| Coverage — RulesEngine.swift | 96.83% lines (88.93% regions) |
| Coverage — PlayerState.swift | 95.00% lines (82.76% regions) |

All 11 new PlayLoopTests listed explicitly in output — all passed.

### TDD Compliance

Per tasks.md, strict TDD is active (`openspec/config.yaml`: `strict_tdd: true`).
Verified by code existence and test-to-implementation mapping (checkboxes
unchecked — bookkeeping gap, not a TDD failure per the verify prompt).

| Task | Test | Code Fix | RED→GREEN Evidence |
|------|------|----------|-------------------|
| 1.2/1.3 | `testPlayResourceRemovesExactlyOneCopy` | `.playResource` — `firstIndex` + `remove(at:)` | ✅ Diff shows `removeAll` → `remove(at:)` |
| 1.4/1.5 | `testPlayUnitRemovesExactlyOneCopy` | `.playUnit` — same pattern | ✅ Same diff |
| 1.6/1.7 | `testPlayBuildingRemovesExactlyOneCopy` | `.playBuilding/.playTechnology/.playSpecial` — same pattern | ✅ Same diff |
| 1.8/1.9 | `testPlayTacticRemovesExactlyOneCopy` | `.playTactic` — index before effects loop, `removeAll` deleted | ✅ Same diff |
| 1.10a | `testPlayResourceNotInHandIsRejected` | Covered by `firstIndex` returning nil | ✅ Guard rejects gracefully |
| 1.10b | `testPlayTacticNotInHandIsRejectedNoEffects` | Covered by `firstIndex` on tacticsHand | ✅ Guard before effects |
| 1.11 | `testPaymentFailureRemovesNothing` | Covered by payment solve failing before remove | ✅ Payment guard before remove |
| 2.1/2.2 | `testSecondResourceSameTurnIsRejected` | Flag field + reset + guard + set | ✅ Separate guard block in commit 82c6623 |
| 2.3 | `testFirstResourceInTurnSucceeds` | Flag set after deploy | ✅ Flag assertion in test |
| 2.4 | `testFlagResetsEachTurn` | Reset at start of `takeTurn` | ✅ `takeTurnForTest` exercises reset |
| 2.5 | `testFailedPaymentDoesNotConsumeSlot` | Guard order: hand → slot → payment | ✅ 3-step payment sequence |

### Test Layer Distribution

| Layer | Count | Tests |
|-------|-------|-------|
| Unit | 11 | All 11 tests are unit tests: construct state inline, call `perform`/`takeTurnForTest` directly, assert state mutations. |
| Integration | 0 | — |
| E2E | 0 | — |

All tests exercise `RulesEngine.perform` or `RulesEngine.takeTurnForTest` via `@testable import`. No YAML loading, no full game loop, no external dependencies. This is appropriate for a correctness fix on core engine mechanics.

### Changed File Coverage

| File | Line Coverage | Region Coverage | Notes |
|------|-------------|-----------------|-------|
| RulesEngine.swift | 96.83% | 88.93% | 3 functions missed (incursion/battle paths not exercised by this suite). All 4 play sites + takeTurn are covered. |
| PlayerState.swift | 95.00% | 82.76% | `hasDeployedResourceThisTurn` field covered by M1-4 tests. Missed regions are `drawEmpire`/`drawTactics` + `strongholdExposed`. |

### Spec Compliance Matrix

| # | Requirement | Scenario | Test | Result |
|---|-------------|----------|------|--------|
| S1 | Single-copy removal | Two identical resource copies | `testPlayResourceRemovesExactlyOneCopy` | ✅ COMPLIANT |
| S2 | Single-copy removal | Two identical unit copies | `testPlayUnitRemovesExactlyOneCopy` | ✅ COMPLIANT |
| S3 | Single-copy removal | Two identical tactic copies | `testPlayTacticRemovesExactlyOneCopy` | ✅ COMPLIANT |
| S4 | Single-copy removal | Single-copy hand emptied | `testPlayResourceRemovesExactlyOneCopy` (hand = `["res_a", "res_a"]` → after play = `["res_a"]`) | ⚠️ PARTIAL — no dedicated single-copy test. The existing test starts with 2 copies and asserts 1 remains. A test starting with exactly 1 copy and asserting 0 remains is not present. The code path is identical (`firstIndex` + `remove(at:)` works for any count ≥ 1), but the spec scenario "single-copy hand is unaffected in count" is not independently pinned. |
| S5 | Single-copy removal | Remaining copy after play is still playable | — | ⚠️ PARTIAL — no test plays the SAME card twice in sequence. The mechanism (index-based removal of one copy) is covered by S1/S2/S3 tests, and the flag-reset test `testFlagResetsEachTurn` exercises playing a resource after a prior turn's deploy. But no test performs `playResource("res_a")` twice in the same turn on a 2-copy hand to prove the second copy is playable and removable. Code path is identical (same guard, same `firstIndex`), but the sequential-two-plays-on-same-id scenario is not pinned. |
| S6 | Single-copy removal | Empty empire hand rejects ALL play actions | `testPlayResourceNotInHandIsRejected` | ⚠️ PARTIAL — only `playResource` is tested with empty hand. The spec says "ALL play actions". No test calls `playUnit`, `playBuilding`, or `playTactic` on an empty hand. Code path is identical for all 4 sites (all use `firstIndex` which returns nil on empty), but only the resource path is explicitly tested. |
| S7 | Single-copy removal | Payment failure removes nothing | `testPaymentFailureRemovesNothing` | ✅ COMPLIANT |
| S8 | Single-copy removal | Valid catalog id not in hand rejected | `testPlayResourceNotInHandIsRejected` + `testPlayTacticNotInHandIsRejectedNoEffects` | ✅ COMPLIANT |
| S9 | Single-copy removal | Valid catalog tactic not in hand, no effects fired | `testPlayTacticNotInHandIsRejectedNoEffects` | ✅ COMPLIANT |
| S10 | One resource per turn | First resource in turn succeeds | `testFirstResourceInTurnSucceeds` | ✅ COMPLIANT |
| S11 | One resource per turn | Second resource same turn rejected | `testSecondResourceSameTurnIsRejected` | ✅ COMPLIANT |
| S12 | One resource per turn | Flag resets at start of each turn | `testFlagResetsEachTurn` | ✅ COMPLIANT |
| S13 | One resource per turn | Failed payment does not consume slot | `testFailedPaymentDoesNotConsumeSlot` | ✅ COMPLIANT |

**Compliance summary**: 10/13 COMPLIANT, 3/13 PARTIAL, 0/13 FAILING, 0/13 UNTESTED

### Coherence (Design)

| Decision | Followed? | Notes |
|----------|-----------|-------|
| D1 — `firstIndex(of:)` + `remove(at:)` | ✅ Yes | All 4 play sites use this pattern. `removeAll` is completely removed. No `removeFirst(where:)` (which doesn't exist). Tactic site correctly resolves index BEFORE effects loop. |
| D2 — Transient turn flag, not persisted | ✅ Yes | `hasDeployedResourceThisTurn` is `var` with default `false`, internal access, no `CodingKeys` involvement. `PlayerState` does not conform to `Codable`. |
| D3 — Flag does not touch `isReady` | ✅ Yes | No coupling to `ResourceInPlay.isReady` or `readyAll()`. The flag is orthogonal. |
| D4 — Reset at exactly one place (start of `takeTurn`) | ✅ Yes | `state.players[playerIdx].hasDeployedResourceThisTurn = false` is the FIRST line of `takeTurn`, before `applyDestinyControlBonus`. |

Rejected alternatives NOT accidentally implemented: confirmed. No `removeFirst(where:)`, no persisted flag, no `isReady` coupling, no multiple reset points.

### Assertion Quality Audit (Step 5f — MANDATORY)

All 11 tests audited:

| Test | Assertions | Quality |
|------|-----------|---------|
| `testPlayResourceRemovesExactlyOneCopy` | `XCTAssertTrue(result.performed)` + `XCTAssertEqual(hand, ["res_a"])` | ✅ Real — verifies production code removes exactly one |
| `testPlayUnitRemovesExactlyOneCopy` | `XCTAssertTrue(result.performed)` + `XCTAssertEqual(hand, ["unit_a"])` | ✅ Real |
| `testPlayBuildingRemovesExactlyOneCopy` | `XCTAssertTrue(result.performed)` + `XCTAssertEqual(hand, ["bldg_a"])` | ✅ Real |
| `testPlayTacticRemovesExactlyOneCopy` | `XCTAssertTrue(result.performed)` + `XCTAssertEqual(tacticsHand, ["tac_a"])` | ✅ Real |
| `testPlayResourceNotInHandIsRejected` | `XCTAssertFalse(result.performed)` + `XCTAssertTrue(result.continueTurn)` | ✅ Real — verifies graceful rejection |
| `testPlayTacticNotInHandIsRejectedNoEffects` | `XCTAssertFalse(performed)` + `XCTAssertTrue(continueTurn)` + `XCTAssertFalse(resource.isReady)` | ✅ Real — 3 assertions pin both rejection AND no side effects |
| `testPaymentFailureRemovesNothing` | `XCTAssertFalse(performed)` + `XCTAssertEqual(hand, ["res_a", "res_a"])` | ✅ Real — verifies no removal on payment failure |
| `testSecondResourceSameTurnIsRejected` | `XCTAssertTrue(first.performed)` + `XCTAssertFalse(second.performed)` + `XCTAssertTrue(second.continueTurn)` + `XCTAssertTrue(hand.contains("res_b"))` | ✅ Real — 4 assertions, all verify production state |
| `testFirstResourceInTurnSucceeds` | `XCTAssertTrue(performed)` + `XCTAssertTrue(hasDeployedResourceThisTurn)` | ✅ Real — verifies flag set |
| `testFlagResetsEachTurn` | `XCTAssertFalse(flag)` × 2 (before/after reset) + `XCTAssertTrue(deployResult.performed)` + `XCTAssertTrue(deployAgain.performed)` | ✅ Real — multi-step, verifies reset cycle |
| `testFailedPaymentDoesNotConsumeSlot` | 6 assertions across 3 perform calls, checking `performed`, `hasDeployedResourceThisTurn`, and hand contents | ✅ Real — most thorough test in the suite |

**No tautologies found.** No `expect(true).toBe(true)` patterns. No assertions without production code calls. No ghost loops over possibly-empty arrays. All assertions verify concrete production state mutations.

### Issues Found

**CRITICAL**:
*(none)*

**WARNING**:

1. **S4 — No dedicated single-copy-to-zero test**: `testPlayResourceRemovesExactlyOneCopy` starts with 2 copies and asserts 1 remains. A scenario starting with exactly 1 copy and asserting 0 remains is not independently tested. Code path is identical but the scenario is not pinned. (PARTIAL)
2. **S5 — No sequential-same-card play test**: No test plays `playResource("res_a")` twice on a 2-copy hand to prove the remaining copy is still playable. The mechanism is proven by the single-play tests, but the Judgment Day F11 intent (pin that index-based removal doesn't corrupt the array on second play) is not directly tested. (PARTIAL)
3. **S6 — Empty hand tested only for resource**: Spec says "empty empire hand rejects ALL play actions". Only `playResource` is tested with empty hand. `playUnit`, `playBuilding`, and `playTactic` on empty hands are untested. Same guard pattern at all 4 sites, but only 1 of 4 is pinned. (PARTIAL)

**SUGGESTION**:

1. Task checkboxes in tasks.md are all unchecked `[ ]` despite all tasks being completed. Bookkeeping gap — not a TDD failure (verified by code), but should be cleaned up before archive.
2. The `#if false` / `#endif` block was correctly removed in commit 82c6623, confirming Phase 2 tests were enabled. Good.

### Verdict

**PASS WITH WARNINGS** — 10/13 COMPLIANT, 3/13 PARTIAL coverage gaps

All 85 tests pass (0 failures). The 3 PARTIAL scenarios share the same root cause: identical code paths that are proven correct for one play type but not independently pinned for all play types. The risk is low (the guard uses the same `firstIndex(of:)` pattern at all 4 sites), but the spec explicitly names these scenarios and an adversarial review should flag them honestly. No CRITICAL issues found. No FAILING tests. Determinism preserved. Design decisions D1–D4 all followed correctly.
