import Foundation

/// Victory and pacing parameters, loaded from `rules_v06.yaml`. These are NOT
/// hardcoded so balance can be tuned without recompiling.
public struct VictoryRules: Codable, Hashable, Sendable {
    /// Outer provinces that must be broken before the Stronghold province is
    /// exposed (default 4 with 5 provinces; lower to 3 for faster games).
    public var outerProvincesToBreakBeforeStronghold: Int
    /// Times the Stronghold province must be broken to win (default 1).
    public var strongholdBreaksToWin: Int
    /// Hard cap on rounds; exceeding it ends the game as a stall (draw).
    public var maxRounds: Int

    public init(outerProvincesToBreakBeforeStronghold: Int = 4,
                strongholdBreaksToWin: Int = 1,
                maxRounds: Int = 20) {
        self.outerProvincesToBreakBeforeStronghold = outerProvincesToBreakBeforeStronghold
        self.strongholdBreaksToWin = strongholdBreaksToWin
        self.maxRounds = maxRounds
    }
}

/// Deck composition requirements, loaded from rules. Used by DeckValidator.
public struct DeckSizeRules: Codable, Hashable, Sendable {
    public var empireTotal: Int
    public var tacticsTotal: Int
    public var empireBreakdown: [String: Int]
    public var tacticsBreakdown: [String: Int]

    public init(empireTotal: Int = 40,
                tacticsTotal: Int = 25,
                empireBreakdown: [String: Int] = [
                    "resource": 16, "unit": 14, "building": 4,
                    "technology": 4, "special": 2
                ],
                tacticsBreakdown: [String: Int] = [
                    "order": 6, "maneuver": 5, "reaction": 5,
                    "formation": 4, "follower": 3, "battlefield": 2
                ]) {
        self.empireTotal = empireTotal
        self.tacticsTotal = tacticsTotal
        self.empireBreakdown = empireBreakdown
        self.tacticsBreakdown = tacticsBreakdown
    }
}

/// Starting hand sizes and initial resources.
public struct SetupRules: Codable, Hashable, Sendable {
    public var startingEmpireHand: Int
    public var startingTacticsHand: Int
    public var startingResourceCount: Int
    public var provincesPerPlayer: Int

    public init(startingEmpireHand: Int = 5,
                startingTacticsHand: Int = 3,
                startingResourceCount: Int = 3,
                provincesPerPlayer: Int = 5) {
        self.startingEmpireHand = startingEmpireHand
        self.startingTacticsHand = startingTacticsHand
        self.startingResourceCount = startingResourceCount
        self.provincesPerPlayer = provincesPerPlayer
    }
}

/// Combat resolution tunables. Lifted out of hardcoded Swift into YAML so the
/// resolver can be calibrated without recompiling (Slice 1.5).
public struct CombatRules: Codable, Hashable, Sendable {
    /// When true, province damage = max(0, attackerPressure - defenderPressure - targetDef).
    public var provinceDamageFromMargin: Bool
    /// Damage applied when an assault wins the battle but raw province damage is
    /// zero — a "floor" so a successful assault never leaves zero progress.
    public var battleWinBonusDamage: Int
    /// When true, defending units that participate in a battle are tapped after
    /// it resolves, even if they won. Models defensive fatigue within a round.
    public var defenderParticipantsTapAfterBattle: Bool
    /// When true, only units that actually participated are tapped (not every
    /// unit on the side, which was the pre-1.5 behavior).
    public var tapOnlyParticipants: Bool
    /// When true, a successful incursion taps one ready defender.
    public var incursionExhaustsDefender: Bool
    /// When true, a successful incursion contests/transfers a Destiny.
    public var incursionContestsDestiny: Bool
    /// When true, incursions resolve with a BattleContext so attacker keywords
    /// apply (each keyword still respects its own gating condition).
    public var incursionAppliesKeywords: Bool
    /// Divisor for casualty computation (margin / divisor = units lost).
    public var casualtyDivisor: Int
    /// Incursion success curve: chance = min(cap, base + slope * margin).
    public var incursionBaseChance: Double
    public var incursionChanceSlope: Double
    public var incursionChanceCap: Double

    public init(provinceDamageFromMargin: Bool = true,
                battleWinBonusDamage: Int = 1,
                defenderParticipantsTapAfterBattle: Bool = true,
                tapOnlyParticipants: Bool = true,
                incursionExhaustsDefender: Bool = true,
                incursionContestsDestiny: Bool = true,
                incursionAppliesKeywords: Bool = true,
                casualtyDivisor: Int = 3,
                incursionBaseChance: Double = 0.25,
                incursionChanceSlope: Double = 0.10,
                incursionChanceCap: Double = 0.85) {
        self.provinceDamageFromMargin = provinceDamageFromMargin
        self.battleWinBonusDamage = battleWinBonusDamage
        self.defenderParticipantsTapAfterBattle = defenderParticipantsTapAfterBattle
        self.tapOnlyParticipants = tapOnlyParticipants
        self.incursionExhaustsDefender = incursionExhaustsDefender
        self.incursionContestsDestiny = incursionContestsDestiny
        self.incursionAppliesKeywords = incursionAppliesKeywords
        self.casualtyDivisor = casualtyDivisor
        self.incursionBaseChance = incursionBaseChance
        self.incursionChanceSlope = incursionChanceSlope
        self.incursionChanceCap = incursionChanceCap
    }
}

/// When and how Destiny control grants its per-round bonus.
public struct DestinyControlRules: Codable, Hashable, Sendable {
    public enum BonusTiming: String, Codable, Hashable, Sendable {
        case startOfControllerRound
        case endOfRound
    }

    public var bonusTiming: BonusTiming
    /// How many resources are untapped per controlled Destiny, per round.
    public var resourceBonusPerRound: Int

    public init(bonusTiming: BonusTiming = .startOfControllerRound,
                resourceBonusPerRound: Int = 1) {
        self.bonusTiming = bonusTiming
        self.resourceBonusPerRound = resourceBonusPerRound
    }
}

/// Aggregated rules document.
public struct Rules: Codable, Hashable, Sendable {
    public var version: String
    public var victory: VictoryRules
    public var decks: DeckSizeRules
    public var setup: SetupRules
    public var combat: CombatRules
    public var destinyControl: DestinyControlRules

    public init(version: String = "0.6",
                victory: VictoryRules = .init(),
                decks: DeckSizeRules = .init(),
                setup: SetupRules = .init(),
                combat: CombatRules = .init(),
                destinyControl: DestinyControlRules = .init()) {
        self.version = version
        self.victory = victory
        self.decks = decks
        self.setup = setup
        self.combat = combat
        self.destinyControl = destinyControl
    }
}

/// Tunable thresholds for balance flags. All values are decimal fractions
/// unless noted (e.g. averageRounds is an absolute count).
public struct BalanceThresholds: Codable, Hashable, Sendable {
    public var strategyOver: Double
    public var strategyUnder: Double
    public var matchupOver: Double
    public var mirrorFirstPlayerOver: Double
    public var averageRoundsOver: Double
    public var averageRoundsUnder: Double
    public var stallRateOver: Double
    public var snowballRateOver: Double
    public var cardDeadRateOver: Double
    public var singleCardWinCorrelationOver: Double

    public init(strategyOver: Double = 0.60,
                strategyUnder: Double = 0.40,
                matchupOver: Double = 0.58,
                mirrorFirstPlayerOver: Double = 0.53,
                averageRoundsOver: Double = 10,
                averageRoundsUnder: Double = 5,
                stallRateOver: Double = 0.30,
                snowballRateOver: Double = 0.35,
                cardDeadRateOver: Double = 0.25,
                singleCardWinCorrelationOver: Double = 0.35) {
        self.strategyOver = strategyOver
        self.strategyUnder = strategyUnder
        self.matchupOver = matchupOver
        self.mirrorFirstPlayerOver = mirrorFirstPlayerOver
        self.averageRoundsOver = averageRoundsOver
        self.averageRoundsUnder = averageRoundsUnder
        self.stallRateOver = stallRateOver
        self.snowballRateOver = snowballRateOver
        self.cardDeadRateOver = cardDeadRateOver
        self.singleCardWinCorrelationOver = singleCardWinCorrelationOver
    }
}
