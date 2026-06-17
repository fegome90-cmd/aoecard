import Foundation
import GameCore

/// SimCLI — headless engine driver for Age of Provinces.
///
/// Commands:
///   info                                    Print engine + data summary.
///   validate                                Validate all decks against rules.
///   simulate --games N --a CIV[:STRAT] --b CIV[:STRAT] --seed S
///                                           Run N games of one matchup.
///   matrix --games N --mode civ|strategy --seed S
///                                           Run all civ- or strategy-pairings.
///   mirrors --games N --seed S              Run each strategy vs itself.
///   export --format csv|json                Re-export the last run (no-op stub).
/// Errors raised while parsing/validating CLI input. These surface through the
/// top-level catch and produce a clean exit(EXIT_FAILURE) — never a runtime
/// trap. Replaces the previous fatalError-based validation (audit BH-01).
struct CLIError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

@main
struct SimCLI {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        do {
            try run(args: args)
        } catch {
            FileHandle.standardError.write(Data("[error] \(error)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    static func run(args: [String]) throws {
        let dataDir = option(args, "data-dir")
        let locator = try DataLocator(override: dataDir)
        let loader = CardLoader(locator: locator)
        let rules = try loader.loadRules()
        let cards = try loader.loadAllCards()
        let decks = try loader.loadAllDecks()
        let destinyDef = try loader.loadDestinyMap()
        let catalog = try loader.loadStrategies()
        let sim = Simulator(cards: cards, rules: rules, decks: decks,
                            strategies: catalog.strategies, destinyDef: destinyDef)

        let command = args.first(where: { !$0.hasPrefix("--") }) ?? "info"
        switch command {
        case "info":
            printInfo(sim: sim, rules: rules, locator: locator)
        case "validate":
            try validate(loader: loader, rules: rules, cards: cards, decks: decks)
        case "simulate":
            try simulate(args: args, sim: sim, rules: rules)
        case "matrix":
            try matrix(args: args, sim: sim, rules: rules)
        case "mirrors":
            try mirrors(args: args, sim: sim, rules: rules)
        case "calibrate":
            try calibrate(args: args, sim: sim, rules: rules)
        case "export":
            // Stub: re-exporting requires persisting the last run path; for the
            // slice, all commands already export to Output/.
            print("export: use simulate/matrix/mirrors, which already export to Output/simulations/")
        default:
            FileHandle.standardError.write(Data("Unknown command: \(command)\n".utf8))
            FileHandle.standardError.write(Data(usage().utf8))
            exit(EXIT_FAILURE)
        }
    }

    static func usage() -> String {
        """
        Usage: SimCLI <command> [options]

        Commands:
          info        Print engine + data summary (default)
          validate    Validate all decks against rules + card db
          simulate    Run N games of a single matchup
          matrix      Run all civ- or strategy-pairings (--mode civ|strategy)
          mirrors     Run each strategy vs itself
          export      (already done by simulate/matrix/mirrors)

        Options:
          --data-dir=PATH   Override Data/ directory location
          --games=N         Number of games per cell (default 1000)
          --a=CIV[:STRAT]   Player A civilization and optional strategy
          --b=CIV[:STRAT]   Player B civilization and optional strategy
          --seed=N          Base RNG seed (default 42)
          --mode=civ|strategy  Matrix mode (matrix only)
        """
    }

    // MARK: - Subcommands

    static func printInfo(sim: Simulator, rules: Rules, locator: DataLocator) {
        print("Age of Provinces — engine loaded")
        print("  rules version : \(rules.version)")
        print("  victory       : break \(rules.victory.outerProvincesToBreakBeforeStronghold) outer → "
              + "stronghold ×\(rules.victory.strongholdBreaksToWin) wins, maxRounds=\(rules.victory.maxRounds)")
        print("  data dir      : \(locator.dataDirectory.path)")
        print("  cards loaded  : \(sim.cards.count)")
        let byCiv = Dictionary(grouping: sim.cards.values, by: { $0.civilization })
        for civ in Civilization.allCases {
            let n = byCiv[civ]?.count ?? 0
            print("    - \(civ.label.padding(toLength: 10, withPad: " ", startingAt: 0)): \(n)")
        }
        print("  decks loaded  : \(sim.decks.count)")
        print("  strategies    : \(sim.strategies.count)")
    }

    static func validate(loader: CardLoader, rules: Rules,
                         cards: [String: Card], decks: [String: DeckList]) throws {
        let validator = DeckValidator(cards: cards, rules: rules)
        var anyInvalid = false
        var totalErrors = 0
        var totalWarnings = 0
        print("Validating \(decks.count) deck(s) against \(cards.count) cards…\n")
        for (deck, result) in validator.validateAll(decks) {
            let status = result.isValid ? "OK  " : "FAIL"
            print("\(status) \(deck.id) (\(deck.civilization.label)) — "
                  + "\(deck.empire.count) empire / \(deck.tactics.count) tactics")
            for f in result.findings.sorted(by: { $0.description < $1.description }) {
                print("    \(f)")
            }
            if !result.isValid { anyInvalid = true }
            totalErrors += result.errors.count
            totalWarnings += result.warnings.count
        }
        print("\n\(totalErrors) error(s), \(totalWarnings) warning(s)")
        if anyInvalid {
            print("DECK VALIDATION FAILED")
            exit(EXIT_FAILURE)
        }
        print("ALL DECKS VALID")
    }

    static func simulate(args: [String], sim: Simulator, rules: Rules) throws {
        let games = intOption(args, "games", default: 1000)
        let seed = try uintOption(args, "seed", default: 42)
        let a = option(args, "a") ?? "mongoles"
        let b = option(args, "b") ?? "britanos"
        let (deckA, stratA) = try resolveSide(a, sim: sim)
        let (deckB, stratB) = try resolveSide(b, sim: sim)

        print("Simulating \(games) games: \(stratA.name) (\(deckA.civilization.label)) "
              + "vs \(stratB.name) (\(deckB.civilization.label)), seed=\(seed)…")
        let results = sim.simulate(deckA: deckA, strategyA: stratA,
                                   deckB: deckB, strategyB: stratB,
                                   games: games, baseSeed: seed)
        let stats = StatsAggregator.matchupStats(label: "\(stratA.name) vs \(stratB.name)", games: results)
        printResult(stats: stats)
        try exportRun(name: "simulate_\(stratA.name)_vs_\(stratB.name)",
                      command: "simulate", games: games, seed: seed,
                      civA: deckA.civilization.label, civB: deckB.civilization.label,
                      stratA: stratA.name, stratB: stratB.name,
                      rulesVersion: rules.version,
                      allGames: results,
                      matchupMatrix: [],
                      strategyMatrix: [(stats.label, results)],
                      mirrorMatrix: [])
    }

    static func matrix(args: [String], sim: Simulator, rules: Rules) throws {
        let games = intOption(args, "games", default: 1000)
        let seed = try uintOption(args, "seed", default: 42)
        let modeStr = option(args, "mode") ?? "strategy"
        // BH-03: reject unknown modes instead of silently coercing to .strategy.
        let mode: Simulator.MatrixMode
        switch modeStr {
        case "civ": mode = .civ
        case "strategy": mode = .strategy
        default:
            throw CLIError(message: "Invalid --mode=\(modeStr): expected 'civ' or 'strategy'")
        }

        print("Running \(mode.rawValue) matrix: \(games) games/cell, seed=\(seed)…")
        let matrix = sim.runMatrix(mode: mode, gamesPerCell: games, baseSeed: seed)
        let allGames = matrix.flatMap { $0.1 }
        print("\n=== \(mode.rawValue) matrix (\(matrix.count) cells, \(allGames.count) games) ===")
        for (cell, games) in matrix {
            let s = StatsAggregator.matchupStats(label: cell, games: games)
            let padded = cell.padding(toLength: 45, withPad: " ", startingAt: 0)
            print(String(format: "  %@ A=%.3f B=%.3f stalls=%.3f avgRounds=%.1f",
                         padded, s.winRateA, s.winRateB, s.stallRate, s.averageRounds))
        }
        try exportRun(name: "matrix_\(mode.rawValue)",
                      command: "matrix --mode \(mode.rawValue)",
                      games: games, seed: seed,
                      rulesVersion: rules.version,
                      allGames: allGames,
                      matchupMatrix: mode == .civ ? matrix : [],
                      strategyMatrix: mode == .strategy ? matrix : [],
                      mirrorMatrix: [])
    }

    static func mirrors(args: [String], sim: Simulator, rules: Rules) throws {
        let games = intOption(args, "games", default: 1000)
        let seed = try uintOption(args, "seed", default: 42)
        print("Running mirror matchups: \(games) games/strategy, seed=\(seed)…")
        let matrix = sim.runMatrix(mode: .mirror, gamesPerCell: games, baseSeed: seed)
        let allGames = matrix.flatMap { $0.1 }
        print("\n=== mirrors (\(matrix.count) cells, \(allGames.count) games) ===")
        for (cell, games) in matrix {
            let s = StatsAggregator.matchupStats(label: cell, games: games)
            let padded = cell.padding(toLength: 45, withPad: " ", startingAt: 0)
            print(String(format: "  %@ firstPlayerWinRate=%.3f stalls=%.3f avgRounds=%.1f",
                         padded, s.firstPlayerWinRate, s.stallRate, s.averageRounds))
        }
        try exportRun(name: "mirrors",
                      command: "mirrors",
                      games: games, seed: seed,
                      rulesVersion: rules.version,
                      allGames: allGames,
                      matchupMatrix: [],
                      strategyMatrix: [],
                      mirrorMatrix: matrix)
    }

    /// Slice 1.5-E: run civ matrix + mirrors, evaluate the 8 calibration gates,
    /// and export a calibration report. Not a unit test — a reproducible numeric
    /// report keyed by seed.
    static func calibrate(args: [String], sim: Simulator, rules: Rules) throws {
        let games = intOption(args, "games", default: 100)
        let seed = try uintOption(args, "seed", default: 42)

        print("Calibrating resolver: \(games) games/cell, seed=\(seed)…")
        let civMatrix = sim.runMatrix(mode: .civ, gamesPerCell: games, baseSeed: seed)
        print("  civ matrix done (\(civMatrix.count) cells)")
        let mirrorMatrix = sim.runMatrix(mode: .mirror, gamesPerCell: games, baseSeed: seed &+ 1)
        print("  mirror matrix done (\(mirrorMatrix.count) cells)")
        let allGames = civMatrix.flatMap { $0.1 } + mirrorMatrix.flatMap { $0.1 }
        print("  allGames=\(allGames.count)")

        // Gate 1: first-player winrate (global, decisive games).
        let decisive = allGames.filter { $0.winner != nil }
        let firstWins = decisive.filter { $0.winner == $0.firstPlayer }.count
        let firstPlayerWinRate = decisive.isEmpty ? 0 : Double(firstWins) / Double(decisive.count)

        // Gates per civilization (offense).
        let civOffense: [Civilization: CivilizationOffenseStats] = Dictionary(
            uniqueKeysWithValues: Civilization.allCases.prefix(3).map {
                ($0, StatsAggregator.civilizationOffenseStats($0, in: allGames))
            }
        )

        // Mirror stall rates: in a deterministic engine, strategy-vs-itself is
        // a perfect symmetry and always stalls — that's not a resolver bug. The
        // meaningful mirror metric is "same civ, different strategies" (cross-
        // strategy), which reveals whether the civ can close symmetric games at
        // all. We run a small cross-strategy mirror per civ on the fly.
        func mirrorStall(_ civ: Civilization) -> Double {
            let civStrats = sim.strategies.filter { $0.civilization == civ }
            guard civStrats.count >= 2,
                  let deck = sim.decks.values.first(where: { $0.civilization == civ }) else {
                return 1.0
            }
            let sA = civStrats[0]
            let sB = civStrats[1]
            let cell = "\(civ.label) cross-mirror"
            let cellSeed = seed &+ 1009 &+ UInt64(civ.rawValue.count)
            let results = sim.simulate(deckA: deck, strategyA: sA,
                                       deckB: deck, strategyB: sB,
                                       games: games, baseSeed: cellSeed)
            return StatsAggregator.matchupStats(label: cell, games: results).stallRate
        }

        // First province broken before round 8.
        let brokenEarly = allGames.filter {
            if let r = $0.firstProvinceBrokenRound { return r < 8 }
            return false
        }.count
        let brokenEarlyRate = allGames.isEmpty ? 0 : Double(brokenEarly) / Double(allGames.count)

        // assaultBattleWinsWithZeroRawProvinceDamage / assaultsSuccessful.
        let totalAssaultWins = allGames.reduce(0) { $0 + $1.assaultsSuccessful }
        let totalZeroRaw = allGames.reduce(0) { $0 + $1.assaultBattleWinsWithZeroRawProvinceDamage }
        let zeroRawRate = totalAssaultWins == 0 ? 1.0 : Double(totalZeroRaw) / Double(totalAssaultWins)

        // Print gate table.
        print("\n=== Calibration gates ===")
        func row(_ label: String, _ value: Double, _ target: String, _ pass: Bool) {
            let mark = pass ? "PASS" : "FAIL"
            print(String(format: "  [%@] %@ %@ (%.3f)", mark, label, target, value))
        }
        row("firstPlayerWinRate (global)", firstPlayerWinRate, "0.47–0.53",
            firstPlayerWinRate >= 0.47 && firstPlayerWinRate <= 0.53)
        for civ in Civilization.allCases.prefix(3) {
            guard let s = civOffense[civ] else { continue }
            row("\(civ.label) assaultBattleWinRate", s.assaultBattleWinRate, ">0.40",
                s.assaultBattleWinRate > 0.40)
            row("\(civ.label) provinceDamagePerAssault", s.provinceDamagePerAssault, ">0.5",
                s.provinceDamagePerAssault > 0.5)
        }
        row("mirror Mongol stall", mirrorStall(.mongoles), "<0.35", mirrorStall(.mongoles) < 0.35)
        row("mirror Britano stall", mirrorStall(.britanos), "<0.55", mirrorStall(.britanos) < 0.55)
        row("mirror Mapuche stall", mirrorStall(.mapuches), "<0.50", mirrorStall(.mapuches) < 0.50)
        row("first province broken < round 8", brokenEarlyRate, ">0.60", brokenEarlyRate > 0.60)
        row("assaultBattleWinsWithZeroRawProvinceDamage", zeroRawRate, "<0.25", zeroRawRate < 0.25)

        // Export calibration_report.json.
        let exporters = Exporters()
        let dir = try exporters.makeRunDir()
        let report = CalibrationReport(
            seed: seed, gamesPerCell: games,
            firstPlayerWinRate: firstPlayerWinRate,
            civilizationOffense: civOffense,
            mirrorStallRates: [
                "mongoles": mirrorStall(.mongoles),
                "britanos": mirrorStall(.britanos),
                "mapuches": mirrorStall(.mapuches)
            ],
            firstProvinceBrokenBeforeRound8Rate: brokenEarlyRate,
            assaultBattleWinsWithZeroRawProvinceDamageRate: zeroRawRate,
            combatRules: rules.combat, destinyControlRules: rules.destinyControl
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: dir.appendingPathComponent("calibration_report.json"))
        try exporters.writeGamesCSV(allGames, to: dir.appendingPathComponent("games.csv"))
        print("\nCalibration report exported to \(dir.path)")
    }

    // MARK: - Export helper

    static func exportRun(name: String, command: String, games: Int, seed: UInt64,
                          civA: String? = nil, civB: String? = nil,
                          stratA: String? = nil, stratB: String? = nil,
                          rulesVersion: String,
                          allGames: [GameResult],
                          matchupMatrix: [(String, [GameResult])],
                          strategyMatrix: [(String, [GameResult])],
                          mirrorMatrix: [(String, [GameResult])]) throws {
        let exporters = Exporters()
        let dir = try exporters.makeRunDir()
        let config = RunConfig(command: command, games: games, seed: seed,
                               civilizationA: civA, civilizationB: civB,
                               strategyA: stratA, strategyB: stratB,
                               rulesVersion: rulesVersion,
                               actualOutputDir: dir.path)
        try exporters.writeRun(name: name, config: config, games: allGames,
                               matchupMatrix: matchupMatrix,
                               strategyMatrix: strategyMatrix,
                               mirrorMatrix: mirrorMatrix,
                               thresholds: BalanceThresholds(),
                               to: dir)
        print("\nExported to \(dir.path)")
    }

    static func printResult(stats: MatchupStats) {
        print(String(format: "  games=%d A=%d B=%d stalls=%d", stats.games, stats.winsA, stats.winsB, stats.stalls))
        print(String(format: "  winRateA=%.4f winRateB=%.4f stalls=%.4f avgRounds=%.2f",
                     stats.winRateA, stats.winRateB, stats.stallRate, stats.averageRounds))
    }

    // MARK: - Arg parsing

    static func option(_ args: [String], _ key: String) -> String? {
        // Accept both "--key=value" and "--key value".
        let prefix = "--\(key)="
        if let v = args.first(where: { $0.hasPrefix(prefix) }) {
            return String(v.dropFirst(prefix.count))
        }
        if let i = args.firstIndex(of: "--\(key)"), i + 1 < args.count {
            let next = args[i + 1]
            if !next.hasPrefix("--") { return next }
        }
        return nil
    }

    static func intOption(_ args: [String], _ key: String, default: Int) -> Int {
        option(args, key).flatMap(Int.init) ?? `default`
    }

    /// Parse a non-negative UInt64 option. Throws CLIError if the user supplied
    /// a value that is not a valid UInt64 (negative, overflow, non-numeric) —
    /// instead of silently falling back to the default (audit BH-04).
    static func uintOption(_ args: [String], _ key: String, default: UInt64) throws -> UInt64 {
        guard let raw = option(args, key) else { return `default` }
        guard let value = UInt64(raw) else {
            throw CLIError(message: "Invalid --\(key)=\(raw): expected a non-negative integer")
        }
        return value
    }

    /// Resolve "mongoles" or "mongoles:Ruta-Incursión" into (deck, strategy).
    /// Throws CLIError on any unknown civ/strategy so the top-level catch
    /// produces a clean exit(1) — never a fatalError trap (audit BH-01).
    static func resolveSide(_ spec: String, sim: Simulator) throws -> (DeckList, Strategy) {
        let parts = spec.split(separator: ":", maxSplits: 1).map(String.init)
        guard !parts.isEmpty, !parts[0].isEmpty else {
            throw CLIError(message: "Empty civilization in side spec: '\(spec)'")
        }
        let civStr = parts[0].lowercased()
        guard let civ = Civilization(rawValue: civStr)
            ?? Civilization.allCases.first(where: { $0.label.lowercased() == civStr }) else {
            throw CLIError(message: "Unknown civilization: \(parts[0])")
        }
        guard let deck = sim.decks.values.first(where: { $0.civilization == civ }) else {
            throw CLIError(message: "No deck for civilization: \(civ.label)")
        }
        let strategy: Strategy
        if parts.count == 2 {
            guard let found = sim.strategies.first(where: {
                $0.name == parts[1] && $0.civilization == civ
            }) else {
                throw CLIError(message: "No strategy '\(parts[1])' for \(civ.label)")
            }
            strategy = found
        } else {
            guard let found = sim.strategies.first(where: { $0.civilization == civ }) else {
                throw CLIError(message: "No strategy for \(civ.label)")
            }
            strategy = found
        }
        return (deck, strategy)
    }
}
