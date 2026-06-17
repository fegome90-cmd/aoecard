import Foundation

/// Per-game result, recorded for every simulated match.
public struct GameResult: Codable, Hashable, Sendable {
    public var matchup: String                  // "Mongoles vs Britanos"
    public var civilizationA: Civilization
    public var civilizationB: Civilization
    public var strategyA: String
    public var strategyB: String
    public var winner: Int?                     // 0, 1, or nil (stall)
    public var winCondition: WinCondition
    public var rounds: Int
    public var firstPlayer: Int                 // who had initiative round 1
    public var firstProvinceBrokenRound: Int?
    public var resourcesWastedFood: Int
    public var resourcesWastedWood: Int
    public var resourcesWastedGold: Int
    public var deadCardsCount: Int
    public var deadTurns: Int
    public var destinyControls: Int             // sum of destiny controls gained by both
    public var incursionsDeclared: Int
    public var incursionsSuccessful: Int
    public var assaultsDeclared: Int
    public var assaultsSuccessful: Int
    public var reactionsPlayed: Int
    public var unitsDestroyed: Int
    public var cardsDrawn: Int
    public var cardsPlayed: Int
    public var strongholdAbilityUses: Int
    public var keywordUses: Int
    public var seed: UInt64

    // Slice 1.5 metrics.
    public var provinceDamageDealt: Int
    public var assaultBattleWinsWithZeroRawProvinceDamage: Int
    public var incursionDefendersExhausted: Int
    public var destinyResourceBonus: Int

    public init(matchup: String, civilizationA: Civilization, civilizationB: Civilization,
                strategyA: String, strategyB: String, winner: Int?,
                winCondition: WinCondition, rounds: Int, firstPlayer: Int,
                firstProvinceBrokenRound: Int? = nil,
                resourcesWastedFood: Int = 0, resourcesWastedWood: Int = 0,
                resourcesWastedGold: Int = 0, deadCardsCount: Int = 0, deadTurns: Int = 0,
                destinyControls: Int = 0, incursionsDeclared: Int = 0,
                incursionsSuccessful: Int = 0, assaultsDeclared: Int = 0,
                assaultsSuccessful: Int = 0, reactionsPlayed: Int = 0,
                unitsDestroyed: Int = 0, cardsDrawn: Int = 0, cardsPlayed: Int = 0,
                strongholdAbilityUses: Int = 0, keywordUses: Int = 0,
                seed: UInt64 = 0,
                provinceDamageDealt: Int = 0,
                assaultBattleWinsWithZeroRawProvinceDamage: Int = 0,
                incursionDefendersExhausted: Int = 0,
                destinyResourceBonus: Int = 0) {
        self.matchup = matchup
        self.civilizationA = civilizationA
        self.civilizationB = civilizationB
        self.strategyA = strategyA
        self.strategyB = strategyB
        self.winner = winner
        self.winCondition = winCondition
        self.rounds = rounds
        self.firstPlayer = firstPlayer
        self.firstProvinceBrokenRound = firstProvinceBrokenRound
        self.resourcesWastedFood = resourcesWastedFood
        self.resourcesWastedWood = resourcesWastedWood
        self.resourcesWastedGold = resourcesWastedGold
        self.deadCardsCount = deadCardsCount
        self.deadTurns = deadTurns
        self.destinyControls = destinyControls
        self.incursionsDeclared = incursionsDeclared
        self.incursionsSuccessful = incursionsSuccessful
        self.assaultsDeclared = assaultsDeclared
        self.assaultsSuccessful = assaultsSuccessful
        self.reactionsPlayed = reactionsPlayed
        self.unitsDestroyed = unitsDestroyed
        self.cardsDrawn = cardsDrawn
        self.cardsPlayed = cardsPlayed
        self.strongholdAbilityUses = strongholdAbilityUses
        self.keywordUses = keywordUses
        self.seed = seed
        self.provinceDamageDealt = provinceDamageDealt
        self.assaultBattleWinsWithZeroRawProvinceDamage = assaultBattleWinsWithZeroRawProvinceDamage
        self.incursionDefendersExhausted = incursionDefendersExhausted
        self.destinyResourceBonus = destinyResourceBonus
    }

    /// Mutating accumulator: fold another result's counters into this one.
    public mutating func accumulate(_ other: GameResult) {
        resourcesWastedFood += other.resourcesWastedFood
        resourcesWastedWood += other.resourcesWastedWood
        resourcesWastedGold += other.resourcesWastedGold
        deadCardsCount += other.deadCardsCount
        deadTurns += other.deadTurns
        destinyControls += other.destinyControls
        incursionsDeclared += other.incursionsDeclared
        incursionsSuccessful += other.incursionsSuccessful
        assaultsDeclared += other.assaultsDeclared
        assaultsSuccessful += other.assaultsSuccessful
        reactionsPlayed += other.reactionsPlayed
        unitsDestroyed += other.unitsDestroyed
        cardsDrawn += other.cardsDrawn
        cardsPlayed += other.cardsPlayed
        strongholdAbilityUses += other.strongholdAbilityUses
        keywordUses += other.keywordUses
        rounds += other.rounds
        provinceDamageDealt += other.provinceDamageDealt
        assaultBattleWinsWithZeroRawProvinceDamage += other.assaultBattleWinsWithZeroRawProvinceDamage
        incursionDefendersExhausted += other.incursionDefendersExhausted
        destinyResourceBonus += other.destinyResourceBonus
    }
}

/// Aggregated stats over a set of games for one (matchup or strategy) cell.
public struct MatchupStats: Codable, Sendable {
    public var label: String
    public var games: Int
    public var winsA: Int
    public var winsB: Int
    public var stalls: Int
    public var averageRounds: Double
    public var stallRate: Double
    public var firstPlayerWinRate: Double        // share of decisive games won by first player
    public var totalIncursionsDeclared: Int
    public var totalAssaultsDeclared: Int
    public var totalUnitsDestroyed: Int
    public var totalKeywordUses: Int

    public init(label: String, games: Int = 0, winsA: Int = 0, winsB: Int = 0,
                stalls: Int = 0, averageRounds: Double = 0, stallRate: Double = 0,
                firstPlayerWinRate: Double = 0, totalIncursionsDeclared: Int = 0,
                totalAssaultsDeclared: Int = 0, totalUnitsDestroyed: Int = 0,
                totalKeywordUses: Int = 0) {
        self.label = label
        self.games = games
        self.winsA = winsA
        self.winsB = winsB
        self.stalls = stalls
        self.averageRounds = averageRounds
        self.stallRate = stallRate
        self.firstPlayerWinRate = firstPlayerWinRate
        self.totalIncursionsDeclared = totalIncursionsDeclared
        self.totalAssaultsDeclared = totalAssaultsDeclared
        self.totalUnitsDestroyed = totalUnitsDestroyed
        self.totalKeywordUses = totalKeywordUses
    }

    public var winRateA: Double { games == 0 ? 0 : Double(winsA) / Double(games) }
    public var winRateB: Double { games == 0 ? 0 : Double(winsB) / Double(games) }
}

/// Computes MatchupStats from a list of GameResult.
public enum StatsAggregator {
    public static func matchupStats(label: String, games: [GameResult]) -> MatchupStats {
        guard !games.isEmpty else { return MatchupStats(label: label) }
        var s = MatchupStats(label: label, games: games.count)
        for g in games {
            switch g.winner {
            case 0: s.winsA += 1
            case 1: s.winsB += 1
            default: s.stalls += 1
            }
            s.totalIncursionsDeclared += g.incursionsDeclared
            s.totalAssaultsDeclared += g.assaultsDeclared
            s.totalUnitsDestroyed += g.unitsDestroyed
            s.totalKeywordUses += g.keywordUses
        }
        s.averageRounds = Double(games.reduce(0) { $0 + $1.rounds }) / Double(games.count)
        s.stallRate = Double(s.stalls) / Double(games.count)

        // First-player win rate: among decisive games, share won by firstPlayer.
        let decisive = games.filter { $0.winner != nil }
        if !decisive.isEmpty {
            let firstWins = decisive.filter { $0.winner == $0.firstPlayer }.count
            s.firstPlayerWinRate = Double(firstWins) / Double(decisive.count)
        }
        return s
    }

    /// Aggregate offensive metrics for a civilization across all its appearances
    /// (as A or B). Used by the `calibrate` command to detect whether a civ
    /// loses because it doesn't attack, or because it attacks but can't close.
    public static func civilizationOffenseStats(_ civ: Civilization,
                                                 in games: [GameResult]) -> CivilizationOffenseStats {
        // Games where this civ appears (as A or B).
        let asA = games.filter { $0.civilizationA == civ }
        let asB = games.filter { $0.civilizationB == civ }

        let assaultsDeclared = asA.reduce(0) { $0 + $1.assaultsDeclared }
                                  + asB.reduce(0) { $0 + $1.assaultsDeclared }
        let assaultsSuccessful = asA.reduce(0) { $0 + $1.assaultsSuccessful }
                                    + asB.reduce(0) { $0 + $1.assaultsSuccessful }
        let incursionsDeclared = asA.reduce(0) { $0 + $1.incursionsDeclared }
                                  + asB.reduce(0) { $0 + $1.incursionsDeclared }
        let incursionsSuccessful = asA.reduce(0) { $0 + $1.incursionsSuccessful }
                                    + asB.reduce(0) { $0 + $1.incursionsSuccessful }
        let provinceDamage = asA.reduce(0) { $0 + $1.provinceDamageDealt }
                              + asB.reduce(0) { $0 + $1.provinceDamageDealt }
        let zeroRawWins = asA.reduce(0) { $0 + $1.assaultBattleWinsWithZeroRawProvinceDamage }
                           + asB.reduce(0) { $0 + $1.assaultBattleWinsWithZeroRawProvinceDamage }

        return CivilizationOffenseStats(
            civilization: civ,
            games: asA.count + asB.count,
            assaultsDeclared: assaultsDeclared,
            assaultsSuccessful: assaultsSuccessful,
            assaultBattleWinRate: assaultsDeclared == 0 ? 0
                : Double(assaultsSuccessful) / Double(assaultsDeclared),
            incursionsDeclared: incursionsDeclared,
            incursionsSuccessful: incursionsSuccessful,
            incursionSuccessRate: incursionsDeclared == 0 ? 0
                : Double(incursionsSuccessful) / Double(incursionsDeclared),
            provinceDamageDealt: provinceDamage,
            provinceDamagePerAssault: assaultsDeclared == 0 ? 0
                : Double(provinceDamage) / Double(assaultsDeclared),
            assaultBattleWinsWithZeroRawProvinceDamage: zeroRawWins
        )
    }
}

/// Per-civilization offensive breakdown (Slice 1.5-E10).
public struct CivilizationOffenseStats: Codable, Sendable {
    public var civilization: Civilization
    public var games: Int
    public var assaultsDeclared: Int
    public var assaultsSuccessful: Int
    public var assaultBattleWinRate: Double
    public var incursionsDeclared: Int
    public var incursionsSuccessful: Int
    public var incursionSuccessRate: Double
    public var provinceDamageDealt: Int
    public var provinceDamagePerAssault: Double
    public var assaultBattleWinsWithZeroRawProvinceDamage: Int
}

/// Slice 1.5 calibration report, exported to `calibration_report.json`.
public struct CalibrationReport: Codable, Sendable {
    public var seed: UInt64
    public var gamesPerCell: Int
    public var firstPlayerWinRate: Double
    public var civilizationOffense: [Civilization: CivilizationOffenseStats]
    public var mirrorStallRates: [String: Double]
    public var firstProvinceBrokenBeforeRound8Rate: Double
    public var assaultBattleWinsWithZeroRawProvinceDamageRate: Double
    public var combatRules: CombatRules
    public var destinyControlRules: DestinyControlRules

    public init(seed: UInt64, gamesPerCell: Int, firstPlayerWinRate: Double,
                civilizationOffense: [Civilization: CivilizationOffenseStats],
                mirrorStallRates: [String: Double],
                firstProvinceBrokenBeforeRound8Rate: Double,
                assaultBattleWinsWithZeroRawProvinceDamageRate: Double,
                combatRules: CombatRules, destinyControlRules: DestinyControlRules) {
        self.seed = seed
        self.gamesPerCell = gamesPerCell
        self.firstPlayerWinRate = firstPlayerWinRate
        self.civilizationOffense = civilizationOffense
        self.mirrorStallRates = mirrorStallRates
        self.firstProvinceBrokenBeforeRound8Rate = firstProvinceBrokenBeforeRound8Rate
        self.assaultBattleWinsWithZeroRawProvinceDamageRate = assaultBattleWinsWithZeroRawProvinceDamageRate
        self.combatRules = combatRules
        self.destinyControlRules = destinyControlRules
    }
}

/// Balance flags computed from a set of stats, using BalanceThresholds.
public struct BalanceFlags: Codable, Sendable {
    public var strategyOver: [String]            // strategies with winrate > threshold
    public var strategyUnder: [String]
    public var matchupOver: [String]
    public var mirrorFirstPlayerOver: [String]
    public var averageRoundsOver: [String]
    public var averageRoundsUnder: [String]
    public var stallRateOver: [String]
    public var snowballRateOver: [String]

    public init(strategyOver: [String] = [], strategyUnder: [String] = [],
                matchupOver: [String] = [], mirrorFirstPlayerOver: [String] = [],
                averageRoundsOver: [String] = [], averageRoundsUnder: [String] = [],
                stallRateOver: [String] = [], snowballRateOver: [String] = []) {
        self.strategyOver = strategyOver
        self.strategyUnder = strategyUnder
        self.matchupOver = matchupOver
        self.mirrorFirstPlayerOver = mirrorFirstPlayerOver
        self.averageRoundsOver = averageRoundsOver
        self.averageRoundsUnder = averageRoundsUnder
        self.stallRateOver = stallRateOver
        self.snowballRateOver = snowballRateOver
    }

    public var hasFlags: Bool {
        !strategyOver.isEmpty || !strategyUnder.isEmpty ||
        !matchupOver.isEmpty || !mirrorFirstPlayerOver.isEmpty ||
        !averageRoundsOver.isEmpty || !averageRoundsUnder.isEmpty ||
        !stallRateOver.isEmpty || !snowballRateOver.isEmpty
    }
}

public enum BalanceAnalyzer {
    public static func compute(strategyStats: [String: MatchupStats],
                               matchupStats: [String: MatchupStats],
                               mirrorStats: [String: MatchupStats],
                               thresholds: BalanceThresholds) -> BalanceFlags {
        var flags = BalanceFlags()
        for (name, s) in strategyStats {
            if s.games >= 30, s.winRateA > thresholds.strategyOver {
                flags.strategyOver.append("\(name): \(String(format: "%.3f", s.winRateA))")
            }
            if s.games >= 30, s.winRateA < thresholds.strategyUnder {
                flags.strategyUnder.append("\(name): \(String(format: "%.3f", s.winRateA))")
            }
            if s.averageRounds > thresholds.averageRoundsOver {
                flags.averageRoundsOver.append("\(name): \(String(format: "%.2f", s.averageRounds))")
            }
            if s.averageRounds < thresholds.averageRoundsUnder {
                flags.averageRoundsUnder.append("\(name): \(String(format: "%.2f", s.averageRounds))")
            }
            if s.stallRate > thresholds.stallRateOver {
                flags.stallRateOver.append("\(name): \(String(format: "%.3f", s.stallRate))")
            }
        }
        for (name, s) in matchupStats {
            // A matchup is flagged when either side's win rate exceeds the
            // threshold. The label names the *dominant* side explicitly so the
            // flag is unambiguous (the cell "A vs B" can favor A or B).
            if s.games >= 30, s.winRateA > thresholds.matchupOver {
                let dominant = name.split(separator: " vs ").first.map(String.init) ?? "A"
                flags.matchupOver.append("\(dominant) dominates \(name): \(String(format: "%.3f", s.winRateA))")
            }
            if s.games >= 30, s.winRateB > thresholds.matchupOver {
                let dominant = name.split(separator: " vs ").dropFirst().first.map(String.init) ?? "B"
                flags.matchupOver.append("\(dominant) dominates \(name): \(String(format: "%.3f", s.winRateB))")
            }
        }
        for (name, s) in mirrorStats {
            if s.games >= 30, s.firstPlayerWinRate > thresholds.mirrorFirstPlayerOver {
                flags.mirrorFirstPlayerOver.append("\(name): \(String(format: "%.3f", s.firstPlayerWinRate))")
            }
        }
        return flags
    }
}
