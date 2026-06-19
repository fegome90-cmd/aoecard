# Tech Debt — Deferred Structural Advisories

These three SwiftLint advisories were intentionally deferred during the
style-cleanup pass (commits 4f15929, 0a5f3b0, 5e78612). They are structural —
fixing them requires real refactoring with a dedicated TDD focus, not a
mechanical rename. The decision to defer was made via Judgment Day (degraded
mode, dual-prior synthesis, both judges converged).

Each entry records: the advisory, why it is structural, the risk of fixing it,
and the suggested approach when it becomes worth doing.

---

## 1. `CombatResolver.resolve()` — cyclomatic complexity 31, body 136+ lines

**Advisory**: `cyclomatic_complexity` (limit 10, current 31), `function_body_length` (limit 100, current ~136).

**File**: `Sources/GameCore/CombatResolver.swift:153`

**Why structural**: The complexity is **inherent**, not accidental. `resolve()`
applies 9 distinct keyword modifiers (Anfibio, Iniciativa, Carga, Anti-Caballería,
Asedio, Guarnecer, Alcance Superior, Mando, plus the effect-bonus pass) in a
strict deterministic order. Each block is a small loop with its own condition.
Splitting into helpers moves ~80 lines across 9 private methods.

**Risk**: The ordering of keyword application is load-bearing for battle
determinism. A careless split can silently reorder modifiers and change game
outcomes. The 14 `KeywordTests` are a partial net but do not cover every
interaction order.

**Suggested approach** (when prioritized):
- Extract one private helper per keyword block: `applyAnfibioBonus`,
  `applyIniciativa`, `applyCarga`, `applyAntiCaballeria`, `applyAsedio`,
  `applyGuarnecer`, `applyAlcanceSuperior`, `applyEffectBonuses`.
- Each helper takes `attacker`/`defender`/`context`/`effects` inout and returns
  the keyword-applied list for stats.
- Call them in the SAME order from `resolve()`. Add an order-regression test
  that pins the exact `keywordsApplied` sequence for a fixed battle fixture.
- Goal: each helper under complexity 5; `resolve()` becomes an orchestrator
  under complexity 10.

---

## 2. `Exporters.writeRun()` — 8 parameters (limit 5)

**Advisory**: `function_parameter_count` (limit 5, current 8).

**File**: `Sources/GameCore/Exporters.swift:50`

**Why structural**: The signature carries 3 matrix buckets
(`matchupMatrix`, `strategyMatrix`, `mirrorMatrix`) plus `name`, `config`,
`games`, `thresholds`, `dir`. Collapsing them requires inventing a parameter
object (a new `RunArtifacts` struct) and updating the single caller in
`SimCLI/main.swift`.

**Risk**: Low — there is exactly one caller (`main.swift:340`). But the change
invents a new public type and reshapes an API contract; doing it as part of a
mechanical style pass risks rushing the type design.

**Suggested approach** (when prioritized):
- Introduce `struct RunArtifacts { let matchupMatrix; let strategyMatrix; let
  mirrorMatrix; let allGames }` (the three buckets already travel together).
- Update `writeRun(name:config:artifacts:thresholds:to:)` to 5 params.
- `RunConfig` already exists as a partial aggregator; consider whether
  `RunArtifacts` should fold into it or stay separate.

---

## 3. `ResourceInPlay.producesKind` — tuple of 3 (large_tuple limit 2)

**Advisory**: `large_tuple` (limit 2 members, current 3).

**File**: `Sources/GameCore/PlayerState.swift:19`

**Why structural**: `producesKind` returns `(food: Bool, wood: Bool, gold: Bool)`.
Fixing it means replacing the tuple with a struct (e.g. `struct ProducesFlags {
let food, wood, gold: Bool }`) and updating every call site. There are **zero
test usages** of `producesKind` today, so the refactor has no safety net.

**Risk**: Medium — it is a public API surface (`ResourceInPlay` is a public
struct in the library product). Changing the return type is a source-breaking
change for any future macOS-UI consumer. Without tests, the refactor cannot be
verified safe.

**Suggested approach** (when prioritized):
- First: add tests that exercise `producesKind` across resource configurations
  (pure-gold, mixed, zero-production, strong/weak-adjusted).
- Then: introduce `struct ResourceKinds: OptionSet` or a named struct and
  migrate callers. Prefer `OptionSet` if the three booleans are treated as a
  set elsewhere; prefer a named struct if they are accessed individually.

---

## Status

Tracked but not blocking. All three are style/architecture advisories — none
affect runtime correctness (verified: 62 tests green as of the cleanup pass).
Address when (a) a feature touches the relevant area, (b) test coverage for the
area reaches a safe threshold, or (c) the engine moves toward a public API
freeze where these contracts matter.
