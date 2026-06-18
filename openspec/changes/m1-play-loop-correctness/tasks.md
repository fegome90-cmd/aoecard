# Tasks: M1 Play-Loop Correctness

> Strict TDD mode is ACTIVE (`openspec/config.yaml`: `strict_tdd: true`,
> `apply.tdd: true`). Every implementation task is preceded by a RED test that
> fails by BEHAVIOR (not by compile error).
> Test command: `swift test --filter <Target>` · Build-tests: `swift build --build-tests`.
> Check off each `- [ ]` as `sdd-apply` completes it.

## Phase 1 — M1-1: Single-copy removal

Goal: replace `removeAll { $0 == id }` (deletes ALL copies) with
`firstIndex(of: id)` + `remove(at:)` (deletes ONE copy) at 4 sites, fusing the
index resolution into the existing guard so it doubles as hand-membership check.
See design.md D1.

> NOTE: an earlier draft prescribed `removeFirst(where:)`. That overload does
> NOT exist in Swift stdlib (verified by compile). Only `firstIndex(of:)` +
> `remove(at:)` is used here.

- [ ] 1.1 Create `Tests/GameCoreTests/PlayLoopTests.swift` scaffold
  - XCTestCase subclass; `private func makeState(...)` helper. Construct minimal
    `Card` stubs inline (id, type, cost, production) — do NOT load YAML in unit
    tests. The helper MUST accept `[String]` for `empireHand`/`tacticsHand`
    directly AND populate `cardsById` so `state.card(for:)` succeeds. Reference
    `ResolverCalibrationTests.makeState` for the catalog-construction pattern.
- [ ] 1.2 RED — M1-1 resource single-copy (behavioral fail)
  - `testPlayResourceRemovesExactlyOneCopy`: hand = `[res_a, res_a]`; perform
    `.playResource("res_a")` with payable cost; assert hand == `[res_a]`.
  - Run → FAIL by behavior (`removeAll` clears both copies, hand == `[]`).
- [ ] 1.3 GREEN — fix `.playResource` site
  - Fuse `firstIndex(of:)` into the guard; `remove(at:)` after commit:

    ```swift
    case .playResource(let id):
        guard let card = state.card(for: id),
              let handIndex = player.empireHand.firstIndex(of: id),
              let payment = Economy.solve(cost: card.cost,
                                          ready: player.readyResources) else {
            return (false, true, 0, false)
        }
        var waste = state.wasteByPlayer[playerIdx]
        Economy.commit(payment, into: &player, wasteSink: &waste)
        state.wasteByPlayer[playerIdx] = waste
        player.empireHand.remove(at: handIndex)
        // ... existing deploy ...
    ```

  - Run filter → 1.2 PASSES.
- [ ] 1.4 RED — M1-1 unit single-copy (behavioral fail)
  - `testPlayUnitRemovesExactlyOneCopy`: hand = `[unit_a, unit_a]`; perform
    `.playUnit("unit_a")`; assert one copy remains.
- [ ] 1.5 GREEN — fix `.playUnit` site (same `firstIndex` + `remove(at:)` pattern).
- [ ] 1.6 RED — M1-1 building/tech/special single-copy (behavioral fail, shared case)
  - `testPlayBuildingRemovesExactlyOneCopy`: hand = `[bldg_a, bldg_a]`; perform
    `.playBuilding("bldg_a")`; assert one remains.
- [ ] 1.7 GREEN — fix shared `.playBuilding/.playTechnology/.playSpecial` site
    (same pattern).
- [ ] 1.8 RED — M1-1 tactic single-copy (behavioral fail)
  - `testPlayTacticRemovesExactlyOneCopy`: tacticsHand = `[tac_a, tac_a]`;
    perform `.playTactic("tac_a")`; assert one remains.
- [ ] 1.9 GREEN — fix `.playTactic` site
  - Different from the other 3 sites: NO payment guard, AND runs an effects
    loop. Resolve the hand index and REMOVE the card BEFORE the effects loop
    (avoids holding an index that could invalidate if a future tactic
    draws/manipulates the hand):

    ```swift
    case .playTactic(let id):
        guard let card = state.card(for: id),
              let handIndex = player.tacticsHand.firstIndex(of: id) else {
            return (false, true, 0, false)
        }
        player.tacticsHand.remove(at: handIndex)
        for effect in card.effects { /* ... resolve effect ... */ }
    ```

  - **IMPORTANT (Judgment Day R3)**: the existing code has `player.tacticsHand.removeAll { $0 == id }`
    AFTER the effects loop (~L279). You MUST DELETE that line — otherwise the
    card is removed twice (once via `remove(at:)`, then `removeAll` scrubs any
    remaining copies). The other 3 sites replace `removeAll` in-place; this
    site MOVES removal, so the stale line is easy to miss.

- [ ] 1.10a REGRESSION — M1-1 resource not-in-hand rejected, no crash (spec S6)
  - `testPlayResourceNotInHandIsRejected`: id in catalog, NOT in hand; perform
    `.playResource`; assert not performed, turn continues, no crash. This is a
    true behavioral RED pre-fix: today the engine accepts a valid-catalog id
    not in the hand (`removeAll` is a silent no-op). Post-fix, `firstIndex`
    returns nil and the guard rejects gracefully.
- [ ] 1.10b REGRESSION — M1-1 tactic not-in-hand rejected, no crash, no effects (spec S7)
  - `testPlayTacticNotInHandIsRejectedNoEffects`: id in catalog, NOT in tactics
    hand, the tactic has effects (`untapResources`). Perform `.playTactic`;
    assert not performed, turn continues, no crash, AND resources/units
    unchanged (no effects fired).
- [ ] 1.11 REGRESSION — M1-1 payment failure removes nothing (spec scenario 5)
  - `testPaymentFailureRemovesNothing`: hand = `[res_a, res_a]`, cost unpayable;
    perform `.playResource`; assert hand unchanged.
- [ ] 1.12 REFACTOR — review the 4 fixed sites. Extract a private helper ONLY
  if it improves clarity without changing semantics. Skip if no gain.

## Phase 2 — M1-4: One resource per turn

Goal: add an INTERNAL `hasDeployedResourceThisTurn` flag (not public — see
design.md Interfaces); reset at start of `takeTurn`; guard + set in
`.playResource`. Single mandated guard order (resolves the 2.2-vs-2.6
contradiction of the prior draft).

- [ ] 2.1 RED — M1-4 second resource same turn rejected (BEHAVIORAL fail)
  - `testSecondResourceSameTurnIsRejected`: hand = `[res_a, res_b]` both payable;
    perform `.playResource("res_a")` (succeeds); perform `.playResource("res_b")`;
    assert res_b NOT deployed, no resources tapped for res_b, turn continues.
  - Run → FAIL by behavior (today both deploy; the test expects res_b rejected).
- [ ] 2.2 GREEN — add field + reset + guard + set
  - **(Judgment Day R3)**: this task RESTRUCTURES the `.playResource` guard
    from task 1.3 (single compound guard) into THREE separate guard blocks.
    The other 3 sites (playUnit, playBuilding, playTactic) remain unchanged
    from Phase 1.
  - `PlayerState.swift`: add INTERNAL `var hasDeployedResourceThisTurn = false`
    (no `public`, no init change — default preserves all call sites). Include
    the doc comment from design.md Interfaces/Contracts.
  - `RulesEngine.swift takeTurn`: reset
    `state.players[playerIdx].hasDeployedResourceThisTurn = false` as the FIRST
    line, before `applyDestinyControlBonus` (design D4).
  - `.playResource` — SINGLE MANDATED ORDER (resolves prior 2.2/2.6 conflict):
    `catalog + hand index → turn-slot check → payment solve → commit → remove one
    card → deploy → set flag → write back`. Exact Swift literal:

    ```swift
    case .playResource(let id):
        guard let card = state.card(for: id),
              let handIndex = player.empireHand.firstIndex(of: id) else {
            return (false, true, 0, false)
        }
        guard !player.hasDeployedResourceThisTurn else {
            return (false, true, 0, false)
        }
        guard let payment = Economy.solve(cost: card.cost,
                                          ready: player.readyResources) else {
            return (false, true, 0, false)
        }
        var waste = state.wasteByPlayer[playerIdx]
        Economy.commit(payment, into: &player, wasteSink: &waste)
        state.wasteByPlayer[playerIdx] = waste
        player.empireHand.remove(at: handIndex)
        // ... existing deploy ...
        player.hasDeployedResourceThisTurn = true
        state.players[playerIdx] = player
        return (true, true, 0, false)
    ```

    Rationale for THIS order: hand membership before turn-slot before payment
    means a rejected deploy (whether for missing card, slot used, or unpayable)
    taps NO resources and removes NO card. Do NOT reorder.
  - Run filter → 2.1 PASSES.
- [ ] 2.3 REGRESSION — M1-4 first resource succeeds (post-GREEN pin)
  - `testFirstResourceInTurnSucceeds`: fresh turn; perform `.playResource("res_a")`
    payable; assert deployed AND flag set.
- [ ] 2.4 REGRESSION — M1-4 flag resets each turn
  - `testFlagResetsEachTurn`: fixture leaves BOTH hands EMPTY so any AI choice
    is `.pass` (the AI cannot play cards); deploy res_a on turn N; call
    `takeTurnForTest` to advance; assert flag is `false` at the start of the
    next turn; THEN insert res_b into hand and call `perform(.playResource("res_b"))`
    directly; assert it succeeds.
- [ ] 2.5 REGRESSION — M1-4 failed payment does not consume slot (spec scenario 8)
  - `testFailedPaymentDoesNotConsumeSlot`. Fixture (precise economy):
    - Starting resource: produces 1 gold.
    - `res_a`: costs 2 gold.
    - `res_b`: costs 0, produces 2 gold.
    - Attempt `.playResource("res_a")` → fails (cannot pay 2 with 1).
    - `.playResource("res_b")` → succeeds (free), now player produces 3 gold.
    - Attempt `.playResource("res_a")` again → would be payable economically,
      BUT the slot is consumed → MUST be rejected.
- [ ] 2.6 REFACTOR — no semantic change. Confirm the `.playResource` body reads
  in the single mandated order above. Do NOT reorder.

## Phase 3 — Regression + determinism

- [ ] 3.1 `swift build --build-tests` exits 0; `swift test` exits 0 with 0
  failures. (Record the test count in the verify report; do NOT pin an absolute
  number in the contract — it goes stale.)
- [ ] 3.2 `SimulationTests.testSameSeedProducesIdenticalResult` MUST still pass
  (same seed → identical state). Absolute outputs MAY shift vs pre-change (the
  bug was masking) — that is expected. The test compares r1 vs r2, not vs
  hardcoded values.
- [ ] 3.3 100-game smoke: no `fatalError`/trap. (Full 1.000-game M1-GATE
  harness is a separate change, Phase 6.)

## Phase 4 — Artifact hygiene

- [ ] 4.1 `lens_diagnostics` clean on edited files (PlayerState, RulesEngine, PlayLoopTests).
- [ ] 4.2 TWO atomic conventional commits inside ONE PR (independent revertability):
  - Commit 1 (right after Phase 1 is GREEN, before starting Phase 2):
    `fix(core): M1-1 single-copy removal`. Stage explicit paths:
    `Sources/GameCore/RulesEngine.swift`, `Tests/GameCoreTests/PlayLoopTests.swift`.
  - Commit 2 (after Phase 2): `fix(core): M1-4 one resource per turn`. Stage:
    `Sources/GameCore/PlayerState.swift`, `Sources/GameCore/RulesEngine.swift`,
    `Tests/GameCoreTests/PlayLoopTests.swift`.
  - Committing Phase 1 immediately after its GREEN avoids `git add -p` hunk
    selection entirely. Stage explicit paths only (never `git add -A`).
  - Selective rollback: `git revert <one commit>`. Full: revert both, reverse order.

## Out of scope (other changes)

- Tactic cost payment / timing windows → `m1-tactics-stronghold` (M1-6, M1-7).
- Building province attachment → `m1-destinies-provinces` (M1-8, M1-10).
- Per-player metrics → `m1-effects-metrics` (M1-9, M1-11).
- 1.000-game M1 gate harness → `m1-victory-gate` (M1-5, M1-GATE).

## Definition of Done

- [ ] All Phase 1 + Phase 2 tasks checked.
- [ ] `swift build --build-tests` exits 0; `swift test` exits 0, 0 failures.
- [ ] `SimulationTests.testSameSeedProducesIdenticalResult` passes.
- [ ] No new public API surface (flag is internal; default value preserves inits).
- [ ] Two atomic commits inside one PR; working tree clean (modulo local
  `.vscode/`, `_ctx/`).
ce (flag is internal; default value preserves inits).
- [ ] Two atomic commits inside one PR; working tree clean (modulo local
  `.vscode/`, `_ctx/`).
