# Design: M1 Play-Loop Correctness

## Technical Approach

Two localized, non-breaking fixes to `RulesEngine.perform()` and one additive
field on `PlayerState`. No new types, no public API removal, no data change.
Both fixes follow strict TDD (RED → GREEN → REFACTOR). The change is designed
to be a single `git revert` rollback — no migration, no on-disk format change.

The two fixes are independent at the code level but ship together because they
share the same review surface (`perform()` + `PlayerState`) and the same
correctness rationale (they are the bugs that invalidate any game state).

## Architecture Decisions

### Decision D1 — `firstIndex(of:)` + `remove(at:)` (M1-1, resolves gate RISK-1)

**Choice**: replace `Array.removeAll { $0 == id }` with `firstIndex(of: id)` +
`remove(at:)` at all four play sites, fused into the existing guard so the
index resolution doubles as the hand-membership check.

> NOTE (2026-06-17 reopen): the earlier version of this decision prescribed
> `removeFirst(where:)`. That overload does **NOT exist** in the Swift stdlib
> (verified by compile: `error: argument passed to call that takes no arguments`).
> Only `removeFirst()` (no args) and `removeFirst(_ n:)` exist. The
> predicate-taking overload does NOT exist symmetric to `removeAll(where:)`.

**Alternatives considered**:

- `removeFirst(where:)`: REJECTED — does not exist in Swift stdlib. (Caught by
  user review after 4 AI judges + orchestrator propagated the error.)
- `contains(id)` guard + `removeFirst(where:)`: rejected for the same reason.
- `firstIndex(of:)` + `remove(at:)` (CHOSEN): one traversal, graceful on
  absent card, removes exactly one copy.

**Rationale**: fusing `let handIndex = player.empireHand.firstIndex(of: id)`
into the existing `guard` accomplishes three things at once: (1) hand-membership
check (the index is nil if absent); (2) graceful rejection (guard fails, action
returns "not performed", no trap); (3) the index needed for `remove(at:)`. It
also avoids double traversal (`contains` + `removeFirst` would walk the array
twice). The catalog lookup (`state.card(for:)`) stays in the same guard to
fetch the `Card` definition — but it no longer pretends to establish hand
membership.

Exact pattern for the 3 empire play sites (resource, unit, building/tech/special):

```swift
guard let card = state.card(for: id),
      let handIndex = player.empireHand.firstIndex(of: id),
      <payment guard if applicable> else {
    return (false, true, 0, false)
}
// ... Economy.commit ...
player.empireHand.remove(at: handIndex)
```

For `.playTactic` (no payment guard, effects loop): resolve the index BEFORE
the effects loop so the card is removed from hand before any effect runs
(avoiding holding an index that could invalidate if a future tactic
draws/manipulates the hand):

```swift
guard let card = state.card(for: id),
      let handIndex = player.tacticsHand.firstIndex(of: id) else {
    return (false, true, 0, false)
}
player.tacticsHand.remove(at: handIndex)
for effect in card.effects { /* ... */ }
```

### Decision D2 — Transient turn flag, derived on load (M1-4, resolves gate F3)

**Choice**: `PlayerState.hasDeployedResourceThisTurn: Bool` is a **transient
runtime field**, NOT persisted. For any future `Codable`/M4-save-load path it
SHALL be **re-derived from turn boundaries**, not serialized.

**Alternatives**:

- Persist the flag as a `CodingKey`: rejected — it is a pure function of "has
  this player taken a play-resource action since the current turn began?",
  which is reconstructable from the action log (M3 replay). Persisting it
  creates two sources of truth that can drift.
- Store as `var` with default `false`, exclude from `CodingKeys`: equivalent to
  transient; same outcome, more ceremony.

**Rationale**: `PlayerState` is not `Codable` today (verified — no `Codable`
conformance declared). When M4 adds save/load, replay-based reconstruction is
the deterministic option. Making the flag transient now avoids a later
serialization refactor and keeps it a pure function of turn boundaries (matches
the spec's Determinism Invariant).

> Swift nuance (Judgment Day F10, corrected 2026-06-17): `PlayerState` does NOT
> currently conform to `Codable`, so the field is not serialized. Swift does
> NOT auto-synthesize conformance spontaneously — synthesis only occurs when a
> type explicitly declares `Codable`/`Encodable`/`Decodable`. If M4 later adds
> a synthesized `Codable` conformance, this field MUST be excluded via
> `CodingKeys` or reconstructed from turn/replay state. The doc comment is
> advisory, not a compile-enforced guard.

### Decision D3 — Flag does not touch the `isReady` invariant (resolves gate F4)

**Choice**: `hasDeployedResourceThisTurn` is a **new single-writer field**. It
does NOT read or write `ResourceInPlay.isReady` and does NOT couple to the
tap/untap lifecycle.

**Alternatives**: none considered — this is a constraint, not a choice.

**Rationale**: `isReady` has a known 3-writer coordination hazard (AF-02,
`docs/tech-debt.md`). The resource-count limit is orthogonal to resource
readiness (a player may have ready resources but have already deployed this
turn). Conflating them would create a 4th writer and worsen AF-02.

### Decision D4 — Reset point is exactly one place

**Choice**: reset `hasDeployedResourceThisTurn = false` at the **start of
`takeTurn(state:playerIdx:)`**, at the start of each player's takeTurn.

**Rationale**: `takeTurn` is the single per-player, per-turn entry point. The
round loop in `play()` (`RulesEngine.swift` ~L100-115) calls `takeTurn` for
**both** players each round via `for turn in 0..<2`, so both flags reset
naturally on their own turn — no separate opponent-reset logic needed.
Resetting at this one point guarantees the flag reflects "this player's current
turn" and avoids double-reset bugs.

> Note (gate RISK-T1): earlier wording said "for the controller only", which
> was misleading. Both players are controllers during their own turns; the code
> resets both flags correctly via the round loop.

## Data Flow

M1-1 (per play action, e.g. `.playResource`):

    .playResource(id)
        │
        ├─ guard card lookup + payment solve ─── (fail) ──► return (false, true)
        │                                                 [no removal, turn continues]
        ├─ Economy.commit(...)        ◄── taps resources
        ├─ empireHand.remove(at: handIndex) ◄── M1-1: removes ONE copy
        ├─ resources.append(...)      ◄── deploy
        └─ return (true, true)

M1-4 (turn lifecycle):

    takeTurn(state, playerIdx)
        │
        ├─ player.hasDeployedResourceThisTurn = false   ◄── D4: single reset
        ├─ applyDestinyControlBonus(...)
        └─ loop (max 8 actions):
              action = ai.choose(...)
              ┌─ .playResource(id):
              │    if player.hasDeployedResourceThisTurn:  ◄── M1-4 guard
              │        return (false, true)   [rejected, turn continues, no cost]
              │    guard payment ... Economy.commit ...
              │    player.hasDeployedResourceThisTurn = true  ◄── set
              │    remove(at: handIndex) ... deploy
              └─ (other actions: unaffected)

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `Sources/GameCore/PlayerState.swift` | Modify | Add `var hasDeployedResourceThisTurn: Bool = false`; init default `false` |
| `Sources/GameCore/RulesEngine.swift` | Modify | At the 4 play sites: fuse `firstIndex(of: id)` into the guard (subsumes hand-membership) and use `remove(at: handIndex)` after commit. `.playTactic`: resolve index + remove BEFORE the effects loop, and DELETE the existing post-loop `removeAll`. Reset flag at start of `takeTurn` (first line, before `applyDestinyControlBonus`); guard + set in `.playResource` (3 separate guard blocks, see tasks.md 2.2). |
| `Tests/GameCoreTests/PlayLoopTests.swift` | Create | RED tests: M1-1 (5 scenarios incl. payment-failure + catalog-but-not-in-hand) + M1-4 (4 scenarios: first-ok, second-rejected, reset, failed-no-consume) |

## Interfaces / Contracts

New stored property — INTERNAL, not public (the engine and `@testable import`
tests are the only consumers; no new public API surface):

```swift
struct PlayerState {
    /// True once this player has deployed a resource during the current turn.
    /// Transient — never serialized; reconstruct from turn boundaries if
    /// persistence is introduced (see D2).
    /// Independent from ResourceInPlay.isReady (see docs/tech-debt.md AF-02).
    var hasDeployedResourceThisTurn = false
    // ...
}
```

The default value preserves every existing initializer call site — no public
init change. No change to `Action`, `GameResult`, or any `Codable` surface.

## Testing Strategy

| Layer | What | Approach |
|-------|------|----------|
| Unit | M1-1 single-copy removal | Build a 2-copy hand via `makeState`/setup; call `.playResource`/`.playUnit`/`.playTactic`; assert one copy remains |
| Unit | M1-4 one-resource/turn | Reset flag, deploy succeeds; second deploy rejected; reset on new turn; failed payment does not consume slot |
| Regression | Determinism | `SimulationTests.testSameSeedProducesIdenticalResult` MUST still pass (same seed → identical state). Note: absolute game outputs will SHIFT vs pre-fix (bug was masking) — that is expected and correct |

All new tests RED before implementation, GREEN after.

## Migration / Rollout

No migration. Rollback = `git revert` of the change commit. No data files,
no YAML, no persisted state touched.

## Open Questions

- None blocking. D2's "re-derive on load" becomes concrete only when M4 adds
  save/load; until then the field is a runtime-only default-false Bool.
