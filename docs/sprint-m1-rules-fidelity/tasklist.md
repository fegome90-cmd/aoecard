# M1 — Rules Fidelity (Sprint Task List)

> **Living document.** One SDD change per phase. Update status + links here after each SDD phase completes.
> Reality-checked against code on **2026-06-17** (HEAD `2382cd6`).

## How to read this

- Each **Phase** = one future SDD change (`openspec/changes/<change-name>/`).
- Each **Task** (M1-* id) = a verified code finding with: the bug, exact files/lines, fix approach, RED test, dependencies, acceptance.
- **Status legend**: `pending` → `sdd-proposal` → `sdd-spec` → `sdd-design` → `sdd-apply` → `sdd-verify` → `done`.

---

## M1 Gate (definition)

The roadmap says: *"1.000 partidas aleatorias sin crash, acciones ilegales ni divergencias deterministas."* Three measurable asserts:

| Gate criterion | How it's measured | Current state |
|---|---|---|
| No crash | 1.000-game batch captures any `throw` / `fatalError` | Partial (74 unit tests pass; no 1k harness yet) |
| No illegal actions | Post-action invariants (resources ≥ 0, ≤ 1 resource/turn, hands ≤ limit, single-copy removal) | **Fails today** (M1-1, M1-4, M1-6 open) |
| No determinism divergence | Same seed × 2 runs → sha256-identical state + log | ✓ closed (REL-03, commit `f1e9298`); scale to 1k |

> Note: "never sees opponent's hand" is **M2 (Legal Actions)**, NOT M1. Do not include it in the M1 gate.

---

## Reality-check: roadmap text vs actual code

The pasted `AOECARD_ROADMAP.md` is **partially stale**. Verified status of each M1 item:

| # | Item (roadmap text) | Real status | Evidence |
|---|---|---|---|
| 1 | Eliminar una sola copia al jugar | 🔴 BUG | `empireHand.removeAll { $0 == id }` deletes **all** copies, not one |
| 2 | Recursos iniciales duplicados | 🔴 BUG | Deck yaml lists ids as starting AND in the empire deck |
| 3 | IDs deterministas | ✅ DONE | commit `f1e9298` (REL-03). Roadmap lists it open → **stale** |
| 4 | Un Recurso por turno | 🔴 MISSING | `takeTurn` allows up to 8 actions, no per-type resource limit |
| 5 | Victoria conectada al YAML | 🟡 PARTIAL | `VictoryRules` exists; `checkVictory()` doesn't reference `rules.victory` directly |
| 6 | Costes y ventanas de tácticas | 🔴 BUG | `playTactic` does NOT pay cost; `Ability.timing` not validated |
| 7 | Habilidades reales de Stronghold | 🔴 MISSING | Stronghold only gives strong/weak + central province |
| 8 | Edificios adjuntos a Provincias | 🔴 MISSING | `playBuilding` → flat `player.permanents`, no province attachment |
| 9 | Efectos defensivos | 🟡 PARTIAL | `battleDefenseBonus`/`provinceDefenseReduction` applied; `grantGarrison` doubtful |
| 10 | Defensa impresa de Destinos | 🔴 MISSING (engine) | `destinies.yaml` has `defense`; `DestinyInPlay` has NO defense field |
| 11 | Métricas separadas por jugador | 🟡 PARTIAL | `wasteByPlayer` is per-player; `LiveCounters` is global |
| 12 | `generic_modifier` en pool | 🔴 PENDING | 37 sites in `Data/cards/*` + `Effect.genericModifier` case |

**Net**: 1 done (M1-3), 3 partial, 8 real bugs/missing. → **9 actionable issues across 6 phases**.

---

## Phase 0 — Close M0 (prerequisite)

> Without a frozen baseline + executable reglamento, M1 has nothing to validate against.

**SDD change**: `m0-baseline-freeze` · **Effort**: ~0.5h · **Status**: `pending`

- [ ] **M0.1** — Freeze baseline + executable reglamento
  - **Deliverable**: git tag `v0.6-baseline`; `docs/reglamento-minimo.md` (fases, pagos, combate, información oculta, victoria).
  - **Dependencies**: none.
  - **Acceptance**: tag exists; reglamento doc covers the 5 areas; `docs/audit-checklist-vs-delivered.md` referenced as M0 output.

---

## Phase 1 — Data cleanup (M1-12)

> Before balancing, placeholders must go. Isolated to data + one enum case; no engine logic change.

**SDD change**: `m1-data-cleanup` · **Effort**: ~2-3h · **Status**: `pending`

- [ ] **M1-12** — Remove `generic_modifier` from the playable pool
  - **Current state**: 37 occurrences across `Data/cards/{mongoles,britanos,mapuches,neutral}.yaml` + `Effect.genericModifier` case (`Effect.swift:25`).
  - **Decision needed (in proposal)**: (a) replace each with a typed effect (slow, 37 cards), or (b) mark those cards `balance.status: banned` and exclude from deck validation (fast, shrinks pool). **Recommended: (b) first** to unblock M1; type them in M5/M6.
  - **Files**: `Data/cards/*.yaml`, `DeckValidator.swift` (exclude `banned`), `Effect.swift` (deprecate case).
  - **RED test**: a banned card cannot enter a valid deck; `generic_modifier` resolves to no-op or is rejected.
  - **Dependencies**: none.

---

## Phase 2 — Play-loop core correctness (M1-1, M1-4) ⚠ CRITICAL

> These invalidate any human game or neural training. **Do first.** Both touch `RulesEngine.perform()` → one cohesive change.

**SDD change**: `m1-play-loop-correctness` · **Effort**: ~3-4h · **Status**: `pending`

- [ ] **M1-1** — Remove ONE copy on play (not all)
  - **Bug**: `player.empireHand.removeAll { $0 == id }` deletes every copy sharing that id.
  - **Sites (4)**: `RulesEngine.swift` — `playResource` (~`:215`), `playUnit` (~`:231`), `playBuilding+Technology+Special` (~`:249`), `playTactic` (`:279` uses `tacticsHand.removeAll`).
  - **Fix**: `removeAll` → `removeFirst { $0 == id }` at all 4 sites.
  - **RED test**: hand with 2 copies of same id; play one; assert 1 remains in hand.
  - **Dependencies**: none (pairs with M1-4 in same change).

- [ ] **M1-4** — One resource per turn
  - **Bug**: `takeTurn` loops up to `maxActions = 8` (`RulesEngine.swift:127`) with no per-type limit; a player can deploy multiple resources/turn.
  - **Fix**: add `hasDeployedResourceThisTurn: Bool` to `PlayerState`; reset at the start of `takeTurn`; reject `playResource` when already true.
  - **Files**: `PlayerState.swift` (new field), `RulesEngine.swift` (reset + validation).
  - **RED test**: deploy resource, attempt second → action rejected (not performed), turn continues.
  - **Dependencies**: none.

---

## Phase 3 — Destinies & provinces (M1-10, M1-8)

> Same area (provinces/destinies); do together to avoid touching `PlayerState` twice.

**SDD change**: `m1-destinies-provinces` · **Effort**: ~4-5h · **Status**: `pending`

- [ ] **M1-10** — Printed defense of Destinies
  - **Bug**: `destinies.yaml` has `defense: 3/4/5` (e.g. `destiny_ruta_de_la_seda`, `destiny_colina_fortificada`) but `DestinyInPlay` (`GameState.swift:38-49`) has **no defense field** → engine drops it.
  - **Fix**: add `defense: Int` to `DestinyInPlay`; load from `card.defense` in `GameSetup.makeDestinyMap`; use where the resolver/incursion reads destiny defense.
  - **Files**: `GameState.swift` (struct + init), `RulesEngine.swift` (consume), `RulesEngine.swift` incursion flow (~`:330-368`).
  - **RED test**: destiny with printed defense 5 reduces incursion damage vs same destiny at defense 0.
  - **Breaking**: `DestinyInPlay.init` signature change → update `makeDestinyMap` + all call sites.

- [ ] **M1-8** — Buildings attached to Provinces
  - **Bug**: `playBuilding` appends to flat `player.permanents` (`RulesEngine.swift:243-252`) — no province adjacency/attachment.
  - **Fix**: model `BuildingInPlay.provinceIndex: Int`; `playBuilding` requires a target province; add `ProvinceInPlay.buildings: [BuildingInPlay]`.
  - **Files**: `PlayerState.swift` (model), `RulesEngine.swift` (`playBuilding`), `Card.swift` (if building effects target province).
  - **RED test**: building without province target → illegal action.
  - **Dependencies**: benefits from M1-10 landing first (shared province model touch).

---

## Phase 4 — Tactics & Stronghold (M1-6, M1-7)

> Depends on Phase 2 (correct play-loop).

**SDD change**: `m1-tactics-stronghold` · **Effort**: ~5-6h · **Status**: `pending`

- [ ] **M1-6** — Tactics pay cost + timing windows
  - **Bug (a)**: `playTactic` case (`RulesEngine.swift:269-303`) does **not** call `Economy.solve`/`commit` → tactics are free.
  - **Bug (b)**: `Ability.timing` exists in `Card.swift` (`:34-39`: battle/action/reaction/passive/roundStart/roundEnd) but is never validated against the current turn phase.
  - **Fix**: (a) mirror the `playResource` payment block in `playTactic`; (b) add a timing guard that rejects a reaction played outside the reaction window, etc.
  - **Files**: `RulesEngine.swift` (`playTactic`), possibly `Rules.swift` (phase enum if not present).
  - **RED test**: tactic with nonzero cost + empty resources → rejected; reaction outside window → rejected.
  - **Dependencies**: Phase 2 (so payment paths are consistent).

- [ ] **M1-7** — Real Stronghold abilities
  - **Bug**: Stronghold only provides `strongWeak` + central province (`isStronghold` flag). The `strongholdAbilityUses` counter is **mis-wired** (increments on tactic `untapResources`, `RulesEngine.swift:295`).
  - **Fix**: design `StrongholdAbility` model (cost, effect, once-per-turn); load from YAML stronghold cards; add new `Action.strongholdAbility`; wire counter correctly.
  - **Files**: new `StrongholdAbility` type, `Card.swift` (field), `DataLoader.swift`, `RulesEngine.swift` (new action case), `StrategyAI.swift` (AI option).
  - **RED test**: activate stronghold ability → effect applied; counter increments exactly once; second activation same turn → rejected.
  - **Dependencies**: Phase 2.

---

## Phase 5 — Effects & metrics (M1-9, M1-11)

> Observability needed to trust the M1 gate.

**SDD change**: `m1-effects-metrics` · **Effort**: ~3-4h · **Status**: `pending`

- [ ] **M1-9** — Audit defensive effects end-to-end
  - **Current state**: `battleDefenseBonus` + `provinceDefenseReduction` applied and tested (`KeywordTests.testProvinceDefenseReductionEffect`). `grantGarrison` (`Effect.swift:22`) application doubtful.
  - **Fix**: trace `grantGarrison` through `EffectApplier`/`RulesEngine`; add RED tests for every defensive effect; document each against the reglamento (Phase 0).
  - **Files**: `EffectApplier.swift`, `RulesEngine.swift`, `KeywordTests.swift` / new `EffectTests.swift`.
  - **RED test**: per defensive effect, assert the defense delta in a minimal battle.
  - **Dependencies**: Phase 0 (reglamento defines intended behavior).

- [ ] **M1-11** — Per-player metrics
  - **Bug**: `LiveCounters` (`RulesEngine.swift:4-`) is **one global instance** (`cardsDrawn`, `cardsPlayed`, `assaultsDeclared`, `keywordUses`, `strongholdAbilityUses`). Only `wasteByPlayer: [ResourceAmount]` is per-player.
  - **Fix**: convert to `[LiveCounters; 2]` (or `LiveCounters { byPlayer: [PlayerCounters; 2] }`); thread `playerIdx` at every increment site; propagate to `GameResult` + `Statistics`.
  - **Files**: `RulesEngine.swift`, `Statistics.swift`, `Simulator.swift`.
  - **RED test**: two players with different action patterns → distinct per-player counters in `GameResult`.
  - **Dependencies**: none (but lands better after Phase 4 so stronghold counters are wired).

---

## Phase 6 — Verify & gate (M1-5 verify, M1-GATE)

> Closes M1.

**SDD change**: `m1-victory-gate` · **Effort**: ~2-3h · **Status**: `pending`

- [ ] **M1-5** — Verify victory is wired to YAML
  - **Current state**: `VictoryRules` (`Rules.swift:139`) + `victory:` in `rules_v06.yaml` exist. But `checkVictory()` (`RulesEngine.swift:509-517`) hardcodes `sp.isBroken && strongholdExposed` and does **not** reference `rules.victory.outerProvincesToBreakBeforeStronghold` / `strongholdBreaksToWin` directly.
  - **Fix (only if test fails)**: wire `rules.victory.*` explicitly in `checkVictory` / `strongholdExposed` computation.
  - **RED test (regression)**: change `outerProvincesToBreakBeforeStronghold` in yaml; assert `checkVictory` honors it. If it already does → close as verified.
  - **Dependencies**: none.

- [ ] **M1-GATE** — 1.000-game determinism + legality harness
  - **Deliverable**: extend `SimulationTests` (or new `M1GateTests`) to a 1.000-game batch asserting: (a) no `throw`/`fatalError`; (b) post-action invariants (resources ≥ 0, ≤ 1 resource/turn, hands ≤ limit, single-copy removal); (c) same seed × 2 → sha256-identical.
  - **Dependencies**: Phases 2-5 done (so invariants actually hold).

---

## Dependency graph

```
Phase 0 (M0) ──┬─→ Phase 1 (M1-12)        [parallel-safe, data only]
               ├─→ Phase 2 (M1-1, M1-4)   ★ CRITICAL, no deps
               │        │
               │        └─→ Phase 4 (M1-6, M1-7)
               │
               └─→ Phase 3 (M1-10 → M1-8)  [M1-10 first, shared province model]
                        │
                        └─→ (informs Phase 4 stronghold targeting)

Phase 0 ──→ Phase 5 (M1-9 needs reglamento; M1-11 standalone, better after P4)

All ──→ Phase 6 (M1-5 verify + M1-GATE)
```

**Critical path**: Phase 0 → Phase 2 → Phase 4 → Phase 6. Phases 1, 3, 5 can interleave/parallelize without blocking.

---

## Effort summary

| Phase | SDD change | Items | Effort |
|---|---|---|---|
| 0 | `m0-baseline-freeze` | M0.1 | ~0.5h |
| 1 | `m1-data-cleanup` | M1-12 | ~2-3h |
| 2 | `m1-play-loop-correctness` | M1-1, M1-4 | ~3-4h |
| 3 | `m1-destinies-provinces` | M1-10, M1-8 | ~4-5h |
| 4 | `m1-tactics-stronghold` | M1-6, M1-7 | ~5-6h |
| 5 | `m1-effects-metrics` | M1-9, M1-11 | ~3-4h |
| 6 | `m1-victory-gate` | M1-5, M1-GATE | ~2-3h |
| | **Total M1** | 9 actionable + 2 verify + 1 done | **~20-25h** |

---

## Changelog

| Date | Change |
|---|---|
| 2026-06-17 | Initial task list created from reality-check analysis (HEAD `2382cd6`). M1-3 marked done. 6 SDD changes scoped. |
