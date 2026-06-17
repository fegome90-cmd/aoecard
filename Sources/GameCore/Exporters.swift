import Foundation

/// Writes simulation results to disk under `Output/simulations/run_YYYYMMDD_HHMM/`.
/// Output files:
///   - summary.json           (run config + aggregate stats + balance flags)
///   - games.csv              (one row per simulated game)
///   - matchup_matrix.csv     (civ-vs-civ or strategy-vs-strategy win rates)
///   - strategy_matrix.csv    (strategy-vs-strategy, when available)
///   - balance_flags.json     (raised balance flags)
public struct Exporters {
    public let outputRoot: URL

    public init(outputRoot: URL? = nil) {
        if let outputRoot {
            self.outputRoot = outputRoot
        } else {
            // Default: <package root>/Output/simulations
            let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            let packageRoot = here.deletingLastPathComponent().deletingLastPathComponent()
            self.outputRoot = packageRoot.appendingPathComponent("Output/simulations")
        }
    }

    /// Make a timestamped run directory and return its URL.
    public func makeRunDir(timestamp: String? = nil) throws -> URL {
        let ts = timestamp ?? Self.timestamp()
        let dir = outputRoot.appendingPathComponent("run_\(ts)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Write all artifacts for a run.
    public func writeRun(name: String,
                         config: RunConfig,
                         games: [GameResult],
                         matchupMatrix: [(String, [GameResult])],
                         strategyMatrix: [(String, [GameResult])],
                         mirrorMatrix: [(String, [GameResult])],
                         thresholds: BalanceThresholds,
                         to dir: URL) throws {
        // games.csv
        try writeGamesCSV(games, to: dir.appendingPathComponent("games.csv"))

        // matchup_matrix.csv
        try writeMatrixCSV(matchupMatrix, to: dir.appendingPathComponent("matchup_matrix.csv"))

        // strategy_matrix.csv
        try writeMatrixCSV(strategyMatrix, to: dir.appendingPathComponent("strategy_matrix.csv"))

        // Aggregate stats for summary + balance flags.
        var matchupStats: [String: MatchupStats] = [:]
        for (cell, games) in matchupMatrix {
            matchupStats[cell] = StatsAggregator.matchupStats(label: cell, games: games)
        }
        var combinedMatrix: [(String, [GameResult])] = strategyMatrix
        combinedMatrix.append(contentsOf: mirrorMatrix)
        let strategyStats = aggregateStrategies(combinedMatrix)
        var mirrorStats: [String: MatchupStats] = [:]
        for (cell, games) in mirrorMatrix {
            mirrorStats[cell] = StatsAggregator.matchupStats(label: cell, games: games)
        }

        let flags = BalanceAnalyzer.compute(strategyStats: strategyStats,
                                            matchupStats: matchupStats,
                                            mirrorStats: mirrorStats,
                                            thresholds: thresholds)

        // balance_flags.json
        try writeJSON(flags, to: dir.appendingPathComponent("balance_flags.json"))

        // summary.json
        let summary = RunSummary(name: name, config: config,
                                 totalGames: games.count,
                                 matchupStats: matchupStats,
                                 strategyStats: strategyStats,
                                 mirrorStats: mirrorStats,
                                 balanceFlags: flags)
        try writeJSON(summary, to: dir.appendingPathComponent("summary.json"))
    }

    // MARK: - Writers

    public func writeGamesCSV(_ games: [GameResult], to url: URL) throws {
        var lines: [String] = []
        lines.append([
            "matchup", "civilizationA", "civilizationB", "strategyA", "strategyB",
            "winner", "winCondition", "rounds", "firstPlayer", "firstProvinceBrokenRound",
            "resourcesWastedFood", "resourcesWastedWood", "resourcesWastedGold",
            "deadCardsCount", "deadTurns", "destinyControls",
            "incursionsDeclared", "incursionsSuccessful",
            "assaultsDeclared", "assaultsSuccessful",
            "reactionsPlayed", "unitsDestroyed", "cardsDrawn", "cardsPlayed",
            "strongholdAbilityUses", "keywordUses", "seed",
            "provinceDamageDealt", "assaultBattleWinsWithZeroRawProvinceDamage",
            "incursionDefendersExhausted", "destinyResourceBonus"
        ].joined(separator: ","))
        for g in games {
            let winnerStr = g.winner.map(String.init) ?? ""
            let firstBrokenStr = g.firstProvinceBrokenRound.map(String.init) ?? ""
            let row: [String] = [
                csv(g.matchup), g.civilizationA.rawValue, g.civilizationB.rawValue,
                csv(g.strategyA), csv(g.strategyB), winnerStr,
                g.winCondition.rawValue, String(g.rounds), String(g.firstPlayer),
                firstBrokenStr,
                String(g.resourcesWastedFood), String(g.resourcesWastedWood), String(g.resourcesWastedGold),
                String(g.deadCardsCount), String(g.deadTurns), String(g.destinyControls),
                String(g.incursionsDeclared), String(g.incursionsSuccessful),
                String(g.assaultsDeclared), String(g.assaultsSuccessful),
                String(g.reactionsPlayed), String(g.unitsDestroyed),
                String(g.cardsDrawn), String(g.cardsPlayed),
                String(g.strongholdAbilityUses), String(g.keywordUses),
                String(g.seed),
                String(g.provinceDamageDealt),
                String(g.assaultBattleWinsWithZeroRawProvinceDamage),
                String(g.incursionDefendersExhausted),
                String(g.destinyResourceBonus)
            ]
            lines.append(row.joined(separator: ","))
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    func writeMatrixCSV(_ matrix: [(String, [GameResult])], to url: URL) throws {
        var lines: [String] = []
        lines.append([
            "cell", "games", "winsA", "winsB", "stalls",
            "winRateA", "winRateB", "averageRounds", "stallRate",
            "firstPlayerWinRate", "totalIncursionsDeclared", "totalAssaultsDeclared",
            "totalUnitsDestroyed", "totalKeywordUses"
        ].joined(separator: ","))
        for (cell, games) in matrix {
            let s = StatsAggregator.matchupStats(label: cell, games: games)
            lines.append([
                csv(cell), String(s.games), String(s.winsA), String(s.winsB), String(s.stalls),
                String(format: "%.4f", s.winRateA), String(format: "%.4f", s.winRateB),
                String(format: "%.2f", s.averageRounds), String(format: "%.4f", s.stallRate),
                String(format: "%.4f", s.firstPlayerWinRate),
                String(s.totalIncursionsDeclared), String(s.totalAssaultsDeclared),
                String(s.totalUnitsDestroyed), String(s.totalKeywordUses)
            ].joined(separator: ","))
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: url)
    }

    // MARK: - Helpers

    /// Aggregate stats per-strategy from a matrix that contains strategy-pair cells.
    /// Each strategy's overall win rate is computed across all its appearances as A.
    func aggregateStrategies(_ matrix: [(String, [GameResult])]) -> [String: MatchupStats] {
        var byStrategy: [String: [GameResult]] = [:]
        for (_, games) in matrix {
            for g in games {
                byStrategy[g.strategyA, default: []].append(g)
            }
        }
        return byStrategy.mapValues { StatsAggregator.matchupStats(label: "", games: $0) }
    }

    /// CSV-quote a string.
    func csv(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    /// Current timestamp as YYYYMMDD_HHMM (local time). Used only for the run
    /// directory name — never affects simulation determinism.
    public static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmm"
        f.timeZone = TimeZone.current
        return f.string(from: Date())
    }
}

/// Run configuration recorded in summary.json.
public struct RunConfig: Codable, Sendable {
    public var command: String
    public var games: Int
    public var seed: UInt64
    public var civilizationA: String?
    public var civilizationB: String?
    public var strategyA: String?
    public var strategyB: String?
    public var rulesVersion: String

    public init(command: String, games: Int, seed: UInt64,
                civilizationA: String? = nil, civilizationB: String? = nil,
                strategyA: String? = nil, strategyB: String? = nil,
                rulesVersion: String) {
        self.command = command
        self.games = games
        self.seed = seed
        self.civilizationA = civilizationA
        self.civilizationB = civilizationB
        self.strategyA = strategyA
        self.strategyB = strategyB
        self.rulesVersion = rulesVersion
    }
}

/// Run summary written to summary.json.
public struct RunSummary: Codable, Sendable {
    public var name: String
    public var config: RunConfig
    public var totalGames: Int
    public var matchupStats: [String: MatchupStats]
    public var strategyStats: [String: MatchupStats]
    public var mirrorStats: [String: MatchupStats]
    public var balanceFlags: BalanceFlags
}
