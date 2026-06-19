# M1 — Rules Fidelity (Sprint Task List)

> **Living document.** One SDD change per phase. Update status + links here after each SDD phase completes.
> Reality-checked against code on **2026-06-17** (HEAD `2382cd6`); updated **2026-06-19** after second user audit verified all remaining items against post-archive HEAD with file:line evidence.

## Current status (2026-06-19)

| Área | Estado |
|---|---|
| Eliminar una copia (M1-1) | ✅ Corregido (archived) |
| Un Recurso por turno (M1-4) | ✅ Corregido (archived) |
| IA respeta límite de Recurso | ✅ Corregido (archived) |
| Desempates deterministas (M1-3) | ✅ Mejorado (observable level) |
| CI básica | ✅ Implementada (build + tests + deck-validate) |
| Recursos iniciales (M1-2) | 🔴 Abierto — **scoping gap closed, added as Phase 1 front** |
| Tácticas (M1-6) | 🔴 Crítico, abierto — tácticas gratuitas |
| Strongholds (M1-7) | 🔴 Crítico, abierto — sin habilidades + bug Mongol-flavor universal |
| Edificios y defensa (M1-8) | 🔴 Abierto — sin provincia, accumulateActiveEffects solo atacante |
| Defensa de Destinos (M1-10) | 🔴 Abierto — DestinyInPlay sin campo defense |
| Victoria desde YAML (M1-5) | 🔴 Abierto — checkVictory hardcodeado |
| Métricas por jugador (M1-11) | 🔴 Abierto — LiveCounters global |
| Instrumentación (M1-13) | 🔴 Abierto — state.round, cardsPlayed, keywordUses, deadCards |
| `generic_modifier` (M1-12) | 🔴 Abierto — 37 sitios |
| Gate de 1.000 partidas | ⏳ Pendiente (Phase 6) |

**Conclusión**: M1 Rules Fidelity **NO está cerrado**. El sprint corrigió 2 bugs fundamentales (M1-1, M1-4) pero el motor aún no representa proporción suficiente de las reglas. **No reanudar balance de cartas** hasta que Phase 6 (gate) pase.

## How to read this

- Each **Phase** = one future SDD change (`openspec/changes/<change-name>/`).
- Each **Task** (M1-* id) = a verified code finding with: the bug, exact files/lines, fix approach, RED test, dependencies, acceptance.
- **Status legend**: `pending` → `sdd-proposal` → `sdd-spec` → `sdd-design` → `sdd-apply` → `sdd-verify` → `done`.

---

## M1 Gate (definition)

The roadmap says: *"1.000 partidas aleatorias sin crash, acciones ilegales ni divergencias deterministas."* Three measurable asserts:

| Gate criterion | How it's measured | Current state |
|---|---|---|
| No crash | 1.000-game batch captures any `throw` / `fatalError` | Partial (89 unit tests pass; no 1k harness yet) |
| No illegal actions | Post-action invariants (resources ≥ 0, ≤ 1 resource/turn, hands ≤ limit, single-copy removal, deck integrity) | **Still fails** — M1-2 (deck dup), M1-6 (free tactics), M1-7 (stronghold), M1-8 (buildings), M1-13 (instrumentation) open |
| No determinism divergence | Same seed × 2 runs → identical OBSERVABLE results (winner, rounds, decisive counters) | ✓ closed at observable level (REL-03 + M1-1). NOTE: full byte-identical state+log is NOT achievable today — entity IDs still default to `UUID()`. The play-loop spec already reduced the contract to "observable results"; **this gate row must be aligned with that** until a deterministic `EntityID` lands (tech-debt). |

> Note: "never sees opponent's hand" is **M2 (Legal Actions)**, NOT M1. Do not include it in the M1 gate.

> CI gap: `.github/workflows/swift.yml` runs build + tests + deck-validate only. The 1.000-game gate harness is NOT in CI yet — it's a separate M1 phase (Phase 7).

---

## Reality-check: roadmap text vs actual code

> Originally verified 2026-06-17 against HEAD `2382cd6`. **Updated 2026-06-19** after M1-1/M1-4 landed (change archived) and a second user audit verified the remaining 8 items against the post-archive HEAD with file:line evidence.

| # | Item (roadmap text) | Real status | Evidence (file:line) |
|---|---|---|---|
| 1 | Eliminar una sola copia al jugar | ✅ DONE | `firstIndex(of:)`+`remove(at:)` fused into guard (RulesEngine.swift 4 sites, commit cb837be) |
| 2 | Recursos iniciales duplicados | 🔴 BUG (no fase asignada — gap de scoping) | `makePlayer` iters `deck.startingResourceIds` to mesa but does NOT remove from `deck.empire` (GameState.swift makePlayer); mongoles YAML has the 3 starting ids appearing 13× in `empire:` |
| 3 | IDs deterministas | ✅ DONE | commit `f1e9298` (REL-03) |
| 4 | Un Recurso por turno | ✅ DONE | internal `hasDeployedResourceThisTurn` flag, reset first-line takeTurn, 3-guard chain in `.playResource` (commit 82c6623); producer-side fix in `StrategyAI.legalActions` (commit 415d349) |
| 5 | Victoria conectada al YAML | 🔴 BUG | `checkVictory()` (RulesEngine.swift) hardcodes `sp.isBroken && strongholdExposed`; **zero reference** to `rules.victory.outerProvincesToBreakBeforeStronghold` / `strongholdBreaksToWin` → editing YAML does nothing |
| 6 | Costes y ventanas de tácticas | 🔴 BUG (CRÍTICO) | `playTactic` (RulesEngine.swift) does NOT call `Economy.solve`/`commit` — tactics are free; only `untapResources`/`untapUnits` processed, `revealTacticsTop` is `break`, rest falls to `default: break` |
| 7 | Habilidades reales de Stronghold | 🔴 MISSING (CRÍTICO) | only `strongWeak` modeled; no Action for activate/cost/once-per-round. **Plus bug**: incursion untaps a gold-producing resource for ALL civs (RulesEngine.swift:443 "Mongol flavor" comment) but executes for britanos/mapuches too, contaminating `strongholdAbilityUses` |
| 8 | Edificios adjuntos a Provincias | 🔴 BUG | `playBuilding` → flat `player.permanents` (RulesEngine.swift:254), no province target; `accumulateActiveEffects` only iterates `attacker.permanents` (RulesEngine.swift:509), ignores defender — British defense effects not evaluated |
| 9 | Efectos defensivos | 🟡 PARTIAL | `battleDefenseBonus`/`provinceDefenseReduction` applied (tested); `grantGarrison` application doubtful; building defensive effects blocked by M1-8 gap |
| 10 | Defensa impresa de Destinos | 🔴 BUG | `destinies.yaml` has `defense: 3/4/5` but `makeDestinyMap` (GameState.swift) creates `DestinyInPlay(cardId:category:traits:)` without `defense`; struct `DestinyInPlay` has NO defense field → Ruta (def 3) y Sitio (def 6) treated equal |
| 11 | Métricas separadas por jugador | 🔴 BUG | `LiveCounters` is ONE global instance (assaults/incursions/cardsPlayed/keywordUses/strongholdUses), not A/B; only `wasteByPlayer` is per-player → civilizationOffenseStats mixes rival actions |
| 12 | `generic_modifier` en pool | 🔴 PENDING | 37 sites in `Data/cards/*` + `Effect.genericModifier` case |
| 13 | Instrumentación (NEW — found 2026-06-19) | 🔴 BUG | (a) `roundsPlayed += 1` but never `state.round += 1` → `firstProvinceBrokenRound` always reports initial round; (b) `cardsPlayed` counts assaults/incursions too; (c) `keywordUses` double-counted (line 138 takeTurn + lines 325/381/431 inside perform); (d) `deadCardsCount`/`deadTurns` hardcoded 0 in makeResult:549 |

**Net updated**: 3 done (M1-1, M1-3, M1-4), 2 partial, **8 real bugs/missing** (M1-2, M1-5, M1-6, M1-7, M1-8, M1-10, M1-11, M1-12) + 1 new instrumentation gap (M1-13). M1-2 was identified in the first audit but never assigned to a phase — that scoping gap is now closed (see Phase 1 below).

---

## Phase 0 — Close M0 (prerequisite)

> Without a frozen baseline + executable reglamento, M1 has nothing to validate against.

**SDD change**: `m0-baseline-freeze` · **Effort**: ~0.5h · **Status**: `pending`

- [ ] **M0.1** — Freeze baseline + executable reglamento
  - **Deliverable**: git tag `v0.6-baseline`; `docs/reglamento-minimo.md` (fases, pagos, combate, información oculta, victoria).
  - **Dependencies**: none.
  - **Acceptance**: tag exists; reglamento doc covers the 5 areas; `docs/audit-checklist-vs-delivered.md` referenced as M0 output.

---

## Phase 1 — Setup integrity + Data cleanup (M1-2, M1-12)

> Before balancing, the deck composition must be honest and placeholders must go. Both are data/setup fixes with minimal engine logic change. **M1-2 goes first** — it invalidates the declared 40-card deck and contaminates any balance conclusion.

**SDD changes**: `m1-starting-deck-integrity` + `m1-data-cleanup` · **Effort**: ~3-4h combined · **Status**: `pending`

- [ ] **M1-2** — Starting resources must leave the empire deck (`m1-starting-deck-integrity`)
  - **Bug (verified 2026-06-19)**: `GameSetup.makePlayer` (GameState.swift) iterates `deck.startingResourceIds` and puts them on the table, but does NOT remove them from `deck.empire`. The 3 starting ids also appear in the empire deck (mongoles YAML: 13× combined). Result: each civ starts with 3 extra cards vs the declared 40-card deck, or keeps copies that should have left.
  - **Decision needed (in proposal)**: (a) the 3 starting cards BELONG to the 40 and must be removed before shuffling; or (b) they are external setup cards not counted in the 40. **Recommended: (a)** — most coherent with the current structure.
  - **Files**: `GameState.swift` (`makePlayer`: filter `deck.empire` to exclude `startingResourceIds`), `DataLoader.swift` (validate counts), tests.
  - **RED test**: after `makePlayer`, `player.empireDeck.count == deck.empire.count - deck.startingResourceIds.count` (no duplicates); same starting id cannot appear both on table and in deck.
  - **Dependencies**: none. **Goes first in Phase 1** — without this, the declared deck size is a lie and any M1-GATE legality check is compromised.

- [ ] **M1-12** — Remove `generic_modifier` from the playable pool (`m1-data-cleanup`)
  - **Current state**: 37 occurrences across `Data/cards/{mongoles,britanos,mapuches,neutral}.yaml` + `Effect.genericModifier` case (`Effect.swift:25`).
  - **Decision needed (in proposal)**: (a) replace each with a typed effect (slow, 37 cards), or (b) mark those cards `balance.status: banned` and exclude from deck validation (fast, shrinks pool). **Recommended: (b) first** to unblock M1; type them in M5/M6.
  - **Files**: `Data/cards/*.yaml`, `DeckValidator.swift` (exclude `banned`), `Effect.swift` (deprecate case).
  - **RED test**: a banned card cannot enter a valid deck; `generic_modifier` resolves to no-op or is rejected.
  - **Dependencies**: ideally after M1-2 (so the deck the validator checks is honest).

---

## Phase 2 — Play-loop core correctness (M1-1, M1-4) ✅ DONE

> These invalidated any human game or neural training. **Was done first.** Both touched `RulesEngine.perform()` → one cohesive change.

**SDD change**: `m1-play-loop-correctness` · **Effort**: ~3-4h (actual: larger — 10 commits, 2 reopens) · **Status**: `done` (archived 2026-06-18 → `openspec/changes/archive/2026-06-18-m1-play-loop-correctness/`)

- [x] **M1-1** — Remove ONE copy on play (not all) ✅
  - **Bug**: `player.empireHand.removeAll { $0 == id }` deleted every copy sharing that id.
  - **Sites (4)**: `RulesEngine.swift` — `playResource`, `playUnit`, `playBuilding+Technology+Special`, `playTactic` (`tacticsHand.removeAll`).
  - **Fix applied** (commit `cb837be`): `firstIndex(of: id)` fused into the existing guard + `remove(at: handIndex)` after commit. NOTE: an earlier plan prescribed `removeFirst(where:)` — **nonexistent API in Swift stdlib**, caught by user audit. The fused `firstIndex+remove(at:)` simultaneously does single-copy removal + hand-membership check + graceful reject (no trap).
  - **Tests**: `testPlayResourceRemovesExactlyOneCopy`, `testPlayUnitRemovesExactlyOneCopy`, `testPlayBuildingRemovesExactlyOneCopy`, `testPlayTacticRemovesExactlyOneCopy`, plus not-in-hand and payment-failure regressions.

- [x] **M1-4** — One resource per turn ✅
  - **Bug**: `takeTurn` looped up to `maxActions = 8` with no per-type limit; a player could deploy multiple resources/turn.
  - **Fix applied** (commit `82c6623`): internal `var hasDeployedResourceThisTurn = false` on `PlayerState`; reset as first line of `takeTurn`; `.playResource` uses 3-guard chain `handIndex → !flag → payment`. Flag set only on successful deploy. Orthogonal to `isReady` (AF-02).
  - **Tests**: `testSecondResourceSameTurnIsRejected`, `testFirstResourceInTurnSucceeds`, `testFlagResetsEachTurn`, `testFailedPaymentDoesNotConsumeSlot` (with no-tap/no-waste assertions).

- [x] **Integration gap (unplanned, found by user audit)** — `StrategyAI.legalActions` producer-side fix
  - **Bug found post-apply**: M1-4 was enforced in `perform()` but `StrategyAI.legalActions()` still offered payable resources after the slot was used → AI burned the 4-consecutive-failure budget → turn early-exit → simulator distortion.
  - **Fix applied** (commit `415d349`): `case .resource` in `legalActions()` now gated by `if !player.hasDeployedResourceThisTurn`. Producer and consumer share one truth.
  - **Test**: `testAIContinuesWithUnitAfterFirstResource` (integration, full turn loop).
  - **Lesson**: when a change introduces a NEW legality criterion, the legal-action PRODUCER must learn it in the same change. Not M2 scope — intrinsic to M1-4.

**Validation trail**: 3 quorum gates (spec/design/tasks) + 3 judgment-day rounds (user caught 1 CRITICAL) + verify (13/13 COMPLIANT, 89 tests) + 4-skill audit quartet × 2 rounds (glm-5.2) + GitHub Actions CI (run 27801312041, macOS-15, 4m35s, success) + user manual audit.

**Known gaps carried forward** (in archive-report.md):

- Suite wall-clock 140s → ~640s local / 4m35s CI (correct behavior, not regression).
- Determinism scoped to "observable results" (UUID defaults still break byte-equality).
- 5 early commits landed direct to main without PR/CI (CI now in place).

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

> Updated 2026-06-19: M1-2 inserted at front of Phase 1 (was a missing scoping). M1-13 folded into Phase 5.

```
Phase 0 (M0.1 reglamento)
    │
    ▼
Phase 1 (M1-2 → M1-12)         ★ M1-2 FIRST: invalidates declared 40-card deck
    │   deck integrity            must land before any balance/gate conclusion
    │   + data cleanup
    ▼
Phase 2 ✅ DONE (M1-1, M1-4)   [archived 2026-06-18]
    │
    ├─→ Phase 4 (M1-6, M1-7)    ★ CRITICAL: tactics free + stronghold absent
    │   tactics + stronghold       + Mongol-flavor bug (line 443)
    │
    └─→ Phase 3 (M1-10 → M1-8)  M1-10 first (DestinyInPlay.defense field),
        destinies + buildings      then M1-8 (buildings need province model
                                  + accumulateActiveEffects must traverse
                                  defender.permanents too)

Phase 5 (M1-9, M1-11, M1-13)   metrics A/B split + instrumentation fixes
    │   (better after Phase 4 so stronghold/tactic counters are real)
    ▼
Phase 6 (M1-5 verify + M1-GATE)  wire checkVictory to rules.victory
                                  + 1000-game harness (CI extension)
```

**Critical path (updated)**: Phase 0 → **Phase 1 (M1-2 first)** → Phase 4 → Phase 6. M1-2 now blocks everything because it invalidates the deck every other phase validates against.

**Do NOT resume card balance until Phase 6 passes.** The engine still misrepresents: deck size (M1-2), tactic cost (M1-6), stronghold abilities (M1-7), building defense (M1-8), destiny defense (M1-10), per-player metrics (M1-11), instrumentation (M1-13). Balance conclusions drawn now would be built on false data.

---

## Effort summary

> Updated 2026-06-19: M1-2 added (was a scoping gap — identified in first audit but never assigned to a phase). M1-13 (instrumentation) added. Phase 1 now covers setup integrity + data cleanup. Tactics/Stronghold (Phase 4) is the largest remaining critical block.

| Phase | SDD change | Items | Effort / Status |
|---|---|---|---|
| 0 | `m0-baseline-freeze` | M0.1 | ~0.5h · pending |
| 1 | `m1-starting-deck-integrity` + `m1-data-cleanup` | M1-2, M1-12 | ~3-4h · pending (M1-2 first) |
| 2 | `m1-play-loop-correctness` ✅ | M1-1, M1-4 | **done 2026-06-18 (archived)** |
| 3 | `m1-destinies-provinces` | M1-10, M1-8 | ~4-5h · pending |
| 4 | `m1-tactics-stronghold` | M1-6, M1-7 | ~5-6h · pending (**CRITICAL** per 2026-06-19 audit) |
| 5 | `m1-effects-metrics` | M1-9, M1-11, M1-13 | ~4-5h · pending (M1-13 instrumentation folded in) |
| 6 | `m1-victory-gate` | M1-5, M1-GATE | ~2-3h · pending |
| | **Total M1 remaining** | 8 actionable items open + 3 done | **~19-23h** |

---

## Changelog

| Date | Change |
|---|---|
| 2026-06-17 | Initial task list created from reality-check analysis (HEAD `2382cd6`). M1-3 marked done. 6 SDD changes scoped. |
| 2026-06-18 | **Phase 2 (`m1-play-loop-correctness`) DONE + archived.** M1-1 (single-copy removal) + M1-4 (one resource per turn) + unplanned StrategyAI.legalActions integration fix. 10 commits, 2 reopens (first: user caught nonexistent `removeFirst(where:)` API that 4 AI judges + I missed; second: user audit caught producer-side gap that 4-skill quartet + verify missed). Validated by 3 quorum gates + 3 judgment-day rounds + verify (13/13, 89 tests) + 4-skill audit × 2 + GitHub Actions CI (first CI run on the repo). Delta spec synced to `openspec/specs/play-loop/spec.md`; change archived to `openspec/changes/archive/2026-06-18-m1-play-loop-correctness/`. Known gaps: suite wall-clock 140s→~640s (correct behavior); determinism scoped to observable results; early commits without CI. |
| 2026-06-19 | **Second user audit — 8 remaining M1 items verified against post-archive HEAD with file:line evidence.** All 8 confirmed real: M1-2 (deck dup, `makePlayer` doesn't filter `deck.empire`), M1-5 (`checkVictory` ignores `rules.victory`), M1-6 (tactics free), M1-7 (stronghold missing + Mongol-flavor bug runs for all civs line 443), M1-8 (buildings flat + `accumulateActiveEffects` attacker-only line 509), M1-10 (`DestinyInPlay` no defense field), M1-11 (`LiveCounters` global not A/B), M1-12 (generic_modifier). New M1-13 found: instrumentation bugs (state.round never incremented, cardsPlayed counts combats, keywordUses double-counted, deadCardsCount/deadTurns hardcoded 0). **Scoping gap closed**: M1-2 was identified in the first audit but never assigned to a phase — now added as `m1-starting-deck-integrity` at the front of Phase 1. Determinism contract contradiction flagged (gate says sha256-identical, M1-1 spec says observable-only — must unify). CI gap noted (no 1000-game gate harness yet). Reality-check table + M1 Gate + effort summary + dependency graph updated with verified evidence. **Conclusion: Rules Fidelity still open; do NOT resume card balance yet.** |
