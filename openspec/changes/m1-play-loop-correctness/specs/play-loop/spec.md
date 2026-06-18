# Spec Delta: play-loop-correctness

> Delta against current behavior. Defines the corrected play-loop semantics
> for M1-1 (single-copy removal) and M1-4 (one resource per turn).
> After verify, this delta merges into `openspec/specs/play-loop/spec.md`.

## Capability: play-loop-correctness

The rules engine MUST mutate hand and per-turn resource state so that a single
play action removes exactly one card copy, and at most one resource is deployed
per turn. These are invariants of any valid game state.

---

## Requirements

### Requirement: Playing a card removes exactly one copy

When a player plays a card by id, the rules engine SHALL remove exactly one
copy of that id from the relevant hand. The engine MUST NOT remove other
copies sharing the same id. This applies to all play actions: resource, unit,
building, technology, special, and tactic.

#### Scenario: hand with two identical resource copies

- **Given** the player's empire hand contains two copies of card id `"res_a"`
- **When** the player performs `playResource("res_a")` and the payment succeeds
- **Then** exactly one copy of `"res_a"` is removed from the empire hand
- **And** the empire hand still contains one copy of `"res_a"`

#### Scenario: hand with two identical unit copies

- **Given** the player's empire hand contains two copies of card id `"unit_a"`
- **When** the player performs `playUnit("unit_a")` and the payment succeeds
- **Then** exactly one copy of `"unit_a"` is removed
- **And** one copy remains in the empire hand

#### Scenario: two identical tactic copies

- **Given** the player's tactics hand contains two copies of card id `"tac_a"`
- **When** the player performs `playTactic("tac_a")`
- **Then** exactly one copy of `"tac_a"` is removed from the tactics hand
- **And** one copy remains in the tactics hand

#### Scenario: single-copy hand is unaffected in count

- **Given** the player's empire hand contains one copy of `"res_a"`
- **When** the player performs `playResource("res_a")` successfully
- **Then** the empire hand no longer contains `"res_a"`

#### Scenario: remaining copy after a play is still playable

- **Given** the player's empire hand contains two copies of `"res_a"`
- **And** the player has already performed `playResource("res_a")` once (one copy removed)
- **When** the player performs `playResource("res_a")` again (and can pay)
- **Then** the second play succeeds and removes the remaining copy
- **And** the empire hand no longer contains `"res_a"`
- (Judgment Day F11: pins that the index-based removal doesn't corrupt the
  array and the guard doesn't reject the second legitimate play.)

#### Scenario: empty empire hand rejects all play actions without crashing

- **Given** the player's empire hand is empty (`[]`)
- **When** the player performs `playResource("res_a")` (id exists in catalog)
- **Then** the action is not performed, no removal attempted, no crash
- **And** the turn continues
- (Judgment Day F9: subsumed by the catalog-but-not-in-hand scenario, but pinned
  explicitly to close the "empty hand vs not-in-hand" gap.)

#### Scenario: payment failure removes nothing

- **Given** the player's empire hand contains two copies of `"res_a"`
- **And** the player cannot pay the cost of `"res_a"`
- **When** the player performs `playResource("res_a")`
- **Then** no copy is removed (the action is not performed)
- **And** the turn continues

#### Scenario: valid catalog id not in hand is rejected without crashing

- **Given** card id `"res_a"` exists in the global card catalog
- **And** the player's empire hand does NOT contain `"res_a"`
- **When** the player performs `playResource("res_a")`
- **Then** the action is not performed (no removal attempted, no resource deployed)
- **And** the turn continues
- **And** the engine does NOT crash (no fatal precondition trap)

#### Scenario: valid catalog tactic not in tactics hand is rejected without crashing and fires no effects

- **Given** tactic id `"tac_a"` exists in the global card catalog
- **And** the player's tactics hand does NOT contain `"tac_a"`
- **And** the tactic `"tac_a"` has effects (e.g. `untapResources`)
- **When** the player performs `playTactic("tac_a")`
- **Then** the action is not performed (no removal attempted)
- **And** NO tactic effects are applied (no resources untapped, no units untapped)
- **And** the turn continues
- **And** the engine does NOT crash
- (Judgment Day C2: pins that the `tacticsHand.contains(id)` guard fires BEFORE
  the effects loop, not just before removal.)

---

### Requirement: At most one resource deployed per turn

A player MAY deploy at most one resource per turn via `playResource`. The
per-turn counter SHALL reset at the start of each player's turn. Attempts
to deploy a second resource in the same turn MUST be rejected as not performed,
and the turn MUST continue (same contract as a failed payment).

#### Scenario: first resource in a turn succeeds

- **Given** it is the start of player 0's turn (flag reset)
- **When** player 0 performs `playResource("res_a")` and pays successfully
- **Then** the resource is deployed to the player's resource row
- **And** the per-turn resource flag is set

#### Scenario: second resource in the same turn is rejected

- **Given** player 0 has already deployed a resource this turn
- **When** player 0 performs `playResource("res_b")`
- **Then** the action is not performed (no card removed, no resource deployed)
- **And** the turn continues (the player may take other actions)
- **And** no cost is paid

#### Scenario: flag resets at the start of each turn

- **Given** player 0 deployed a resource on the previous round
- **When** a new turn for player 0 begins
- **Then** the per-turn resource flag is reset to false
- **And** player 0 MAY deploy one resource on this new turn

#### Scenario: rejected resource does not consume the slot

- **Given** player 0 has not deployed a resource this turn
- **And** the player's starting resource produces 1 gold
- **And** `"res_a"` costs 2 gold; `"res_b"` costs 0 gold and produces 2 gold
- **When** player 0 attempts `playResource("res_a")` → fails (cannot pay 2 with 1)
- **And** player 0 then performs `playResource("res_b")` → succeeds (free; now produces 3 gold)
- **And** player 0 attempts `playResource("res_a")` again → economically payable now, BUT the slot is consumed
- **Then** the third attempt is REJECTED (the slot was consumed by `res_b`)
- **And** `"res_a"` is NOT removed from hand; no resources tapped for the third attempt

---

## Non-Goals

- Tactic cost payment and timing windows (Phase 4, `m1-tactics-stronghold`).
- Building attachment to provinces (Phase 3, `m1-destinies-provinces`).
- Per-player metrics / counters (Phase 5, `m1-effects-metrics`).
- Any change to the `Action` enum surface or to YAML data.

## Determinism Invariants (load-bearing)

- The per-turn resource flag is a pure function of turn boundaries; it MUST NOT
  depend on any non-deterministic source (UUIDs, wall clock, random).
- Card removal order MUST remain deterministic: `firstIndex(of:)` + `remove(at:)`
  removes the first matching copy in existing hand array order, which is
  seed-derived. No sort or shuffle is introduced by this change.
- Same seed + same action sequence SHALL produce byte-identical game state and
  log before and after this change, modulo the corrected hand contents.
e, modulo the corrected hand contents.
