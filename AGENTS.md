# AGENTS.md

Repository-level instructions for AI coding agents working on **Age of Provinces (aoecard)**.

## Purpose

aoecard is a game engine and simulation CLI written in Swift. Game entities — cards, rules, decks — are **data-driven**, loaded from external YAML. The engine must be **bit-for-bit deterministic**: the same seed and action sequence reproduces the same state and log.

## Layout

- `Sources/GameCore/` — Core engine library: rules, game state, combat. **All domain logic lives here.**
- `Sources/SimCLI/` — Thin CLI entry point for validation and simulation. **No domain logic here.**
- `Data/` — Canonical game data as YAML. **This is source.** Add cards/rules by editing YAML, not by hardcoding values.
- `Tests/GameCoreTests/` — XCTest suite.
- `Output/simulations/` — Generated output. **Not in git** (see `.gitignore`); reproduce via SimCLI.

## Tech Stack

- Swift 6.0 tools-version (Swift 6.3.x toolchain), macOS 13.0+
- Swift Package Manager (SPM) — no Xcode project required
- Yams 5.2.0 — the single external dependency. Pure-Swift YAML parser, no system deps. Justified because YAML is the canonical data format and Swift has no built-in YAML parser.

## Commands

All commands run from the repo root.

```bash
swift build                       # Build GameCore + SimCLI (does NOT compile tests)
swift build --build-tests         # Also compile the test target — run this to catch test-side compile errors
swift test                        # Full XCTest suite (expect ~74 tests, 0 failures)
swift test --filter GameCoreTests # Single test target
swift test --filter KeywordTests  # Single test class (use case-sensitive name)
swift test --enable-code-coverage # Coverage report
swift run SimCLI                  # Run the simulation CLI
```

There is **no lint or format tooling** configured. Do not invent a `lint`/`format` command.

## Architecture Rules

- **Library/CLI split** — keep all rules and state in `GameCore`. `SimCLI` is a thin entry point only.
- **Data-driven** — add new cards/rules by editing `Data/*.yaml`, never by hardcoding values in Swift.
- **Clean IO boundary** — `DataLoader` owns all file IO and YAML parsing (Yams → `Codable`). Keep IO out of `GameCore` domain logic.
- **Determinism is load-bearing** — never introduce non-deterministic tie-breaks (e.g. `UUID` string ordering on random UUIDs). Order by stable array index or seed-derived data. See `SimulationTests.testSameSeedProducesIdenticalResult` for the contract.

## Testing Conventions

- **Strict TDD mode (enabled)** — write a failing test in `Tests/GameCoreTests` (XCTest) **first**, then implement. No production code without a failing test. Follow RED → GREEN → REFACTOR.
- **Immutability** — prefer value types (`struct`, `let`) and pure functions in the domain.
- **Battle-determinism invariants** — the order in which `CombatResolver.resolve()` applies keyword modifiers is load-bearing. See `KeywordTests.testResolveAppliesKeywordsInDocumentedOrder` before touching `resolve()`.

## Editing Guardrails

- Modify only the files needed for the task.
- Prefer minimal, reversible changes.
- **Validate before completion**: run `swift build --build-tests`, then `swift test` (or at least the filtered suite touching your change). Both must pass.
- Use exception chaining and catch specific errors first when adding Swift error handling.

## Persistence (SDD artifacts)

SDD change artifacts live in **OpenSpec** under `openspec/changes/<change-name>/` (proposal → spec → design → tasks → apply → verify → sync → archive). Per-sprint backlog and technical detail live in `docs/sprint-<milestone>/`.

> Override note (2026-06-17): an earlier convention stored SDD artifacts in engram. The active sprint uses OpenSpec. Update this section if the project settles on a different default.

## Do Not Commit

These are in `.gitignore` — never stage them:

`.build/`, `.swiftpm/`, `*.xcodeproj`, `xcuserdata/`, `DerivedData/`, `Output/simulations/`, `.atl/`, `.pi/`, `.claude/`, `.trifecta/`, `.fork/`, `.netrc`, `.DS_Store`

Reproduce generated outputs; never store them. Stage explicit paths only — never `git add -A` or `git add .`.

## References

- `README.md` — project overview and badges
- `docs/audits/2026-06-17-audit-checklist-vs-delivered.md` — audit findings traceability (which fixes landed, which are open)
- `docs/architecture/tech-debt.md` — deferred structural advisories (`resolve()` complexity, `writeRun` params, `producesKind` tuple)
- `docs/sprints/m1-rules-fidelity/tasklist.md` — active M1 sprint backlog (6 SDD changes, verified per-item code references)
