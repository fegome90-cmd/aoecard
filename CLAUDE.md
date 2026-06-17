# CLAUDE.md — Age of Provinces (aoecard)

> Project-specific context for Claude Code. Complements (does not replace) the global `~/.claude/CLAUDE.md`.

## Project Overview

**Age of Provinces (aoecard)** is a game engine and simulation CLI written in Swift.
Game entities — cards, rules, decks — are **data-driven**, loaded from external YAML files.

- **GameCore** — Core engine library: business logic, rules, game state.
- **SimCLI** — Command-line entry point for validation and simulation runs.
- **Data/** — Canonical game data as YAML. This **is** source.
- **Output/simulations/** — Generated simulation output. **Not** in git (see `.gitignore`); reproduce via SimCLI.

## Tech Stack

- **Swift 6.0** tools-version (Swift 6.3.x toolchain), **macOS 13.0+**
- **Swift Package Manager (SPM)** — no Xcode project required
- **Yams 5.2.0** — the single external dependency; a pure-Swift YAML parser with no system dependencies. Justified because YAML is the canonical data format and Swift has no built-in YAML parser.

## Common Commands

```bash
swift build                       # Build GameCore + SimCLI
swift run SimCLI                  # Run the simulation CLI
swift test                        # Full XCTest suite
swift test --filter GameCoreTests # Single test target
swift test --enable-code-coverage # Coverage report
```

## Architecture

- **Library/CLI split** — all business logic lives in `GameCore`; `SimCLI` is a thin entry point. **Do not put domain logic in the CLI.**
- **Data-driven** — add new cards/rules by editing `Data/*.yaml`, not by hardcoding values.
- **Clean IO boundary** — `DataLoader` owns all file IO and YAML parsing (Yams → `Codable`). `GameCore` focuses on rules and state; keep IO out of the domain layer.
- **Standard SPM layout** — `Sources/GameCore`, `Sources/SimCLI`, `Tests/GameCoreTests`.

## Testing & Conventions

- **Strict TDD mode (enabled)** — write a failing test in `Tests/GameCoreTests` (XCTest) first, then implement. No production code without a failing test.
- **Immutability** — prefer value types (`struct`, `let`) and pure functions in the domain.
- **Persistence** — SDD artifacts live in **engram** (not files). Recover via `mem_search` with topic key `sdd/{change}/...` (e.g. `sdd/db-config/explore` for the DB-integration discussion).

## Do Not Commit

`.build/`, `Output/simulations/`, `.swiftpm/`, `DerivedData/`, `.atl/`, `.pi/` — all in `.gitignore`. Reproduce outputs; never store generated artifacts.
