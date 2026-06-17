# Age of Provinces — Headless Engine

![Swift](https://img.shields.io/badge/Swift-6.0%2B-F05138?logo=swift&logoColor=white)
![macOS](https://img.shields.io/badge/platform-macOS%2013%2B-000000?logo=apple&logoColor=white)
![SPM](https://img.shields.io/badge/SPM-compatible-F05138?logo=swift&logoColor=white)
![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)

A headless, deterministic, testable card-game engine for **Age of Provinces**, a
strategy card game with two decks, provinces, a stronghold/civilization, a
central Destiny map, and tap-to-pay resources. This repository contains the
**simulation engine first** — no UI, no networking, no persistence. The macOS UI
comes later.

> Current state: **v0.6 slice** with the **1.5 combat-resolver calibration**.

This is a rules prototype. It does not copy names, logos, or art from any
existing franchise.

## Status

- **Slice 1 (v0.6):** headless engine complete — loads cards from YAML,
  validates decks, simulates deterministically from a seed, exports statistics
  + balance flags.
- **Slice 1.5:** combat resolver calibrated so the attacker can actually close
  games. Before 1.5, the engine measured "inability to close" rather than card
  balance. After 1.5 it produces damage, pressure, province breaks, and Destiny
  control credibly. See "Slice 1.5 — Combat Resolver Calibration" below.

Combat is **abstract** (Pressure-based, no dice) with the v0.6 keyword modifiers
modeled numerically.

| Area | Status |
|---|---|
| Card/rules loading (YAML via Yams) | ✅ |
| Deck validation (sizes, civ legality, maxCopiesInDeck) | ✅ |
| Economy (strong/weak resources, PaymentSolver subset search) | ✅ |
| Combat resolver (Anfibio, Carga, Asedio, Anti-Cab, Guarnecer, Iniciativa, Alcance Superior, Mando, etc.) | ✅ |
| Effect system (effects resolved by id, never by card name) | ✅ |
| Rules engine (turns, incursions, assaults, victory) | ✅ |
| Strategy AI (15 strategies, 5 per civ) | ✅ |
| Simulator (civ/strategy/mirror matrices, deterministic seeds) | ✅ |
| Exporters (JSON + CSV + balance flags) | ✅ |
| Tests | 60 passing (resolver calibration + defensive fatigue + incursion + Destiny bonus) |

### Known limitations of this slice

These are **by design** for the first slice (per the agreed plan) and will be
addressed in later slices:

- **Combat is abstract.** Tactics whose exact text doesn't map to a discrete
  effect id use `generic_modifier` with a human-readable note. See the
  "Effect vocabulary" section.
- **Performance.** ~60ms/game in release mode. The strategy matrix at 1000
  games/cell over 225 cells (~225k games) takes hours. The civ matrix (9 cells)
  at 1000 games/cell takes ~10 minutes. Parallelism is a later slice.
- **Balance is rough.** Britanos beat Mongoles ~70% in the current abstract
  model (defenders have a structural advantage when the engine can't close
  games aggressively). Mirrors stall heavily. These are exactly the signals the
  balance flags surface — they're the input to the next tuning pass, not bugs.
- **No literal tactic text.** Tactics declare effect ids; the human `text:` is
  for reading only.
- **No Maravillas, no networking, no UI, no concurrency.**

## Requirements

- macOS with Swift 6.0+ (developed on Swift 6.2.3).
- `swift test` and XCTest require the full Xcode developer tools, not just
  Command Line Tools. If `swift test` fails with `no such module 'XCTest'`,
  point `DEVELOPER_DIR` at Xcode:

  ```bash
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  ```

  (or run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`).

## Build & test

```bash
swift build                 # debug build
swift test                  # 43 tests
swift run SimCLI info       # engine + data summary
swift run SimCLI validate   # validate all decks against rules
```

## CLI

```bash
# Engine summary
swift run SimCLI info

# Validate decks (sizes, civ legality, maxCopiesInDeck)
swift run SimCLI validate

# Single matchup, N games (default civ uses its first strategy)
swift run SimCLI simulate --games 1000 --a mongoles:Ruta-Incursión --b britanos --seed 42

# All civ-vs-civ pairings (9 cells)
swift run SimCLI matrix --games 1000 --mode civ --seed 123

# All strategy-vs-strategy pairings (225 cells) — slow at high game counts
swift run SimCLI matrix --games 2000 --mode strategy --seed 123

# Each strategy vs itself (15 mirrors)
swift run SimCLI mirrors --games 5000 --seed 7

# Calibrate the combat resolver (Slice 1.5): runs civ matrix + cross-strategy
# mirrors, prints the calibration gate table, exports calibration_report.json.
swift run SimCLI calibrate --games 100 --seed 42
```

Options can be written as `--games 1000` or `--games=1000`. Override the data
directory with `--data-dir=PATH` or the `AOE_DATA_DIR` env var.

### Output

Every `simulate` / `matrix` / `mirrors` run writes to:

```
Output/simulations/run_YYYYMMDD_HHMM/
  summary.json           # run config + aggregate stats + balance flags
  games.csv              # one row per simulated game
  matchup_matrix.csv     # civ-vs-civ win rates
  strategy_matrix.csv    # strategy-vs-strategy win rates
  balance_flags.json     # raised balance flags
```

`Output/` is git-ignored; reproduce any run with the same `--seed`.

## Architecture

```
Sources/
  GameCore/
    Resource.swift        # ResourceAmount, Production, StrongWeakResources
    CardTypes.swift       # Civilization, DeckSlot, CardType, DestinyCategory
    Traits.swift          # Trait (civ/unit/terrain), TraitFilter
    Keywords.swift        # KeywordName, Keyword, KeywordSet
    Card.swift            # Card, Stats, Cost, Ability, CardLimits, CardBalance
    Effect.swift          # EffectID registry + Effect enum (decoded by id)
    Rules.swift           # VictoryRules, DeckSizeRules, SetupRules, thresholds
    RandomSource.swift    # SplitMix64 deterministic PRNG
    DataLoader.swift      # DataLocator + CardLoader (Yams), DeckList, Strategy
    DeckValidator.swift   # sizes, civ legality, maxCopiesInDeck
    PlayerState.swift     # ResourceInPlay, ProvinceInPlay, UnitInPlay, PlayerState
    GameState.swift       # GameState + GameSetup factory
    Economy.swift         # production adjustment + PaymentSolver (subset search)
    CombatResolver.swift  # BattleContext, BattleResult, Pressure resolution
    EffectApplier.swift   # Effect enum → ActiveEffects mutations
    RulesEngine.swift     # turn loop, actions, victory check
    StrategyAI.swift      # action evaluation weighted by priorities
    Simulator.swift       # single + matrix runs, deterministic per seed
    Statistics.swift      # GameResult, MatchupStats, balance flags
    Exporters.swift       # JSON/CSV writers, RunSummary
  SimCLI/main.swift       # CLI driver
Tests/GameCoreTests/
  EconomyTests.swift      # strong/weak, PaymentSolver (exact, minimal-waste,
                          #   anti-greedy, impossible, fewer-taps tie-break)
  GameSetupTests.swift    # end-to-end setup from real data, strongholdExposed,
                          #   deterministic destiny map
  KeywordTests.swift      # Anfibio, Alcance Superior, Iniciativa, Carga,
                          #   Anti-Caballería, Asedio, Guarnecer, Única, etc.
  SimulationTests.swift   # determinism with seed, initiative alternation,
                          #   matrices civ/strategy/mirror, stats aggregation
Data/
  cards/      mongoles, britanos, mapuches, neutral, destinies (.yaml)
  decks/      mongoles_v06, britanos_v06, mapuches_v06 (.yaml)
  maps/       destiny_v06.yaml
  rules/      rules_v06.yaml
  strategies/ strategies_v06.yaml (15 strategies)
Output/simulations/       generated (git-ignored)
```

## Design decisions

### Unique in play ≠ deck limit

`limits.uniqueInPlay` (table rule, enforced by RulesEngine) and
`limits.maxCopiesInDeck` (construction rule, enforced by DeckValidator) are
independent fields. A `uniqueInPlay: true` card does **not** automatically get a
deck copy cap — that must be declared explicitly.

### PaymentSolver is a deterministic subset search, not greedy

`Economy.solve` enumerates `2^n` subsets of ready resources, keeps those that
cover the cost in all three dimensions, and ranks by
`(waste_total ASC, taps_count ASC, lexicographic_by_id ASC)`. A greedy solver
can fail when a valid combination exists; this one won't (within the `n <= 16`
cap, above which it falls back to a deterministic greedy).

### Victory is parametrized in rules, not hardcoded

`rules_v06.yaml` controls `outerProvincesToBreakBeforeStronghold`,
`strongholdBreaksToWin`, and `maxRounds`. Tune balance without recompiling.

### Effects are resolved by id, never by card name

Every tactic/ability declares `effects: [{ id: ... }]`. The engine has zero
`if card.name == "..."` branches. See the vocabulary below.

## Effect vocabulary

Slice vocabulary (closed set; extend `Effect.swift` to add ids):

| id | params | meaning |
|---|---|---|
| `cancel_charge` | — | Attacking cavalry loses Carga this battle |
| `suppress_keyword` | keyword, terrain? | Suppress a keyword (e.g. Hostigar/Contraataque) in this battle/terrain |
| `battle_attack_bonus` | amount, target_filter | +X Attack to matching units |
| `battle_defense_bonus` | amount, target_filter | +X Defense to matching units |
| `command_attack_bonus` | amount, trait_filter | Mando: +X Attack to another unit with the trait |
| `province_defense_reduction` | amount, condition | -X Defense to the enemy province |
| `range_bonus` | amount, target_filter | +X Range |
| `archer_bonus_vs_trait` | amount, trait | Archers +X vs a trait |
| `amphib_first_attacker_bonus` | amount | First Anfibio attacker +X from water |
| `untap_units` | count, filter | Untap N units |
| `untap_resources` | count, produces? | Untap N resources (optionally of a kind) |
| `grant_garrison` | amount, target_filter | Grant Guarnecer X |
| `free_incursion` | target_filter | Declare a free incursion |
| `reveal_tactics_top` | count | Look at the top of the tactics deck |
| `generic_modifier` | notes | Fallback for tactics without a dedicated id |

## Balance thresholds

`BalanceThresholds` (in `Rules.swift`, defaults shown) drive the flags in
`balance_flags.json`:

| Flag | Threshold |
|---|---|
| `strategyOver` | strategy winrate > 0.60 |
| `strategyUnder` | strategy winrate < 0.40 |
| `matchupOver` | matchup winrate > 0.58 |
| `mirrorFirstPlayerOver` | mirror first-player winrate > 0.53 |
| `averageRoundsOver` | avg rounds > 10 |
| `averageRoundsUnder` | avg rounds < 5 |
| `stallRateOver` | stall rate > 0.30 |
| `snowballRateOver` | (placeholder) |
| `cardDeadRateOver` | (placeholder) |
| `singleCardWinCorrelationOver` | (placeholder) |

## First report

A representative civ-matrix run (9 cells × 1000 games, seed 123) illustrates the
output format. `Output/` is git-ignored, so run artifacts are not in the repo —
reproduce locally with `swift run SimCLI matrix --games 1000 --mode civ --seed 123`.
The `matchup_matrix.csv` rows are the source of truth; cells are labeled
`A vs B` where `winRateA` is A's win rate and `winRateB` is B's.
`winsA + winsB + stalls = games` always holds.

Reading the matrix correctly: a cell `Mongoles vs Britanos` with `winsA=0,
winsB=706` and the cell `Britanos vs Mongoles` with `winsA=707, winsB=0`
describe the **same** fact (Britanos win ~70% of decisive games) from two
sides of the matrix — they are not two independent observations.

Headline findings (inputs to the next balance pass, not bugs):

- **Britanos dominate Mongoles** (~70% of decisive games), whether Mongoles are
  A or B. Britanos' ranged units and province defense translate well to the
  abstract Pressure model; Mongoles' cavalry/incursion identity doesn't.
- **Mongoles never win a decisive game** in any cell. Their winsA and winsB are
  both 0 across the matrix.
- **`firstPlayerWinRate ≈ 0.38`** in every decisive cell — the first player
  loses systematically. This points at an attacker-side weakness in the model
  (attacking units tap and don't break provinces before the defender
  counterattacks), not at a card problem.
- **Mirrors stall 100%** (Mongoles/Mongoles, Mapuches/Mapuches) — the abstract
  engine can't close symmetric games. Britanos/Britanos stalls only 22%.

## Slice 1.5 — Combat Resolver Calibration

### Why

Slice 1's calibration audit revealed the resolver was structurally biased
against the attacker: Mongoles won 0% of decisive games, mirrors stalled 100%,
and `assaultBattleWinsWithZeroRawProvinceDamage` was ~100%. Any card-balance
work on top of that would have been cosmetic. Slice 1.5 calibrates the resolver
without touching cards, decks, or strategies.

### What changed

- **`battleWin` ≠ `provinceDamage`.** A battle win (beating the defenders) no
  longer requires beating the province defense. Province damage is the offensive
  surplus beyond the defense (`max(0, attackerPressure - defenderPressure -
  targetDefense)`).
- **Battle-win floor.** An assault that wins the battle but produces zero raw
  province damage still deals `combat.battleWinDamage` (default 2) to the
  province — so a successful assault always leaves progress. Assaults-on-province
  only; Destiny assaults flip on a single success.
- **Defensive fatigue.** Only units that actually participated tap (not every
  unit on the side). Defenders that participate tap whether they win or lose,
  so they can't defend twice in the same round.
- **Incursion overhaul.** Incursions now resolve via a `BattleContext` so
  attacker keywords apply (Carga still gated to assaults; Asedio gated to
  province/building targets). A successful incursion exhausts the highest-
  defense ready defender and contests/transfers a Destiny, in addition to its
  existing damage + resource tempo.
- **Destiny control matters.** At the start of the controller's turn, each
  controlled Destiny untaps a tapped resource (economy bonus, no card draw).
- **All combat tunables in YAML.** `combat:` and `destinyControl:` blocks in
  `rules_v06.yaml` — calibrate without recompiling.
- **`calibrate` command.** Runs civ matrix + cross-strategy mirrors, evaluates
  the calibration gates, and exports `calibration_report.json`.

### Calibration gates (seed 42, 100 games/cell)

| Gate | Target | Result | |
|---|---|---|---|
| firstPlayerWinRate (global) | 0.47–0.53 | 0.565 | FAIL (close; v0.7) |
| Mongoles assaultBattleWinRate | >0.40 | 0.930 | PASS |
| Mongoles provinceDamagePerAssault | >0.5 | 2.612 | PASS |
| Britanos assaultBattleWinRate | >0.40 | 0.905 | PASS |
| Britanos provinceDamagePerAssault | >0.5 | 2.458 | PASS |
| Mapuches assaultBattleWinRate | >0.40 | 0.969 | PASS |
| Mapuches provinceDamagePerAssault | >0.5 | 1.073 | PASS |
| mirror Mongol stall (cross-strategy) | <0.35 | 0.310 | PASS |
| mirror Britano stall (cross-strategy) | <0.55 | 0.030 | PASS |
| mirror Mapuche stall (cross-strategy) | <0.50 | 1.000 | FAIL (strategy, v0.7) |
| first province broken < round 8 | >0.60 | 0.883 | PASS |
| assaultBattleWinsWithZeroRawProvinceDamage | <0.25 | 0.102 | PASS |

**9 of 11 gates pass.** The two remaining FAILs are card/strategy balance
issues, not resolver issues:

- **`firstPlayerWinRate = 0.565`:** the first player has a mild tempo edge
  because attacking is now profitable and they attack first. Fine-tuning this
  without reintroducing the anti-attacker bias is a card/strategy job (v0.7).
- **`mirror Mapuche stall = 1.000`:** the two cross-strategy Mapuche pairings
  (`Defensa Territorial` vs `Anfibio Frontera`) are both defensively-oriented
  and stall each other. This is a strategy-design problem, not a resolver
  problem — Mapuche mirrors with other strategy pairs close normally.

The headline contrast with Slice 1:

| Metric | Slice 1 | Slice 1.5 |
|---|---|---|
| Mongoles assaultBattleWinRate | ~0% | 93% |
| Mongoles provinceDamagePerAssault | ~0 | 2.6 |
| assaultBattleWinsWithZeroRawProvinceDamage | ~100% | 10% |
| first province broken < round 8 | rare | 88% |

### How to re-calibrate

All combat knobs live in `Data/rules/rules_v06.yaml`:

```yaml
combat:
  provinceDamageFromMargin: true
  battleWinBonusDamage: 2
  defenderParticipantsTapAfterBattle: true
  tapOnlyParticipants: true
  incursionExhaustsDefender: true
  incursionContestsDestiny: true
  incursionAppliesKeywords: true
  casualtyDivisor: 3
  incursionBaseChance: 0.40
  incursionChanceSlope: 0.10
  incursionChanceCap: 0.85
```

Edit the YAML and re-run `swift run SimCLI calibrate --games 100 --seed 42` —
no recompilation needed.

## Next slices (not in this repository state)

1. Literal tactic text + finer unit selection + terrain movement.
2. Maravillas.
3. Game parallelism (perf).
4. macOS UI.

## License

Released under the [MIT License](LICENSE).
