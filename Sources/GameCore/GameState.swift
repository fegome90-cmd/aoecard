import Foundation

/// Why a game ended.
public enum WinCondition: String, Codable, Hashable, Sendable {
    case strongholdBroken    // attacker broke the defender's stronghold province
    case concession          // (not used in v0.6 simulation)
    case stall               // maxRounds reached without a winner
}

/// A destiny card placed on the central map. Only its traits matter for combat.
public struct DestinyInPlay: Hashable, Sendable {
    public let cardId: String
    public let category: DestinyCategory
    public let traits: Set<Trait>
    /// Owning player index, or nil if neutral/contested.
    public var controller: PlayerIndex?

    public init(cardId: String, category: DestinyCategory,
                traits: Set<Trait>, controller: PlayerIndex? = nil) {
        self.cardId = cardId
        self.category = category
        self.traits = traits
        self.controller = controller
    }
}

/// Whole-game state. All randomness flows through `rng`; the same seed and the
/// same sequence of `rng` draws reproduce the game bit-for-bit.
public struct GameState: Sendable {
    public var players: [PlayerState]       // [player0, player1]
    public var destinyMap: [DestinyInPlay]  // 5 entries, one per category
    public var round: Int
    /// Index of the player who has initiative this round.
    public var current: PlayerIndex
    public var rng: RandomSource
    public let rules: Rules
    /// Card database by id (for the rules engine + AI to look up definitions).
    public let cardsById: [String: Card]

    /// Accumulated wasted resources per player (for stats).
    public var wasteByPlayer: [ResourceAmount]

    public init(players: [PlayerState], destinyMap: [DestinyInPlay],
                round: Int, current: PlayerIndex, rng: RandomSource, rules: Rules,
                cardsById: [String: Card]) {
        self.players = players
        self.destinyMap = destinyMap
        self.round = round
        self.current = current
        self.rng = rng
        self.rules = rules
        self.cardsById = cardsById
        self.wasteByPlayer = [ResourceAmount.zero, ResourceAmount.zero]
    }

    public mutating func setCurrent(_ index: PlayerIndex) { current = index }

    /// Alternate initiative at the end of the round.
    public mutating func alternateInitiative() {
        current = current == 0 ? 1 : 0
    }

    /// Subscript convenience.
    public subscript(_ i: PlayerIndex) -> PlayerState {
        get { players[i] }
        set { players[i] = newValue }
    }
}

/// Factory: build the initial GameState from a pair of deck lists + cards +
/// destiny map definition, all seeded by a deterministic RNG.
public enum GameSetup {
    public enum SetupError: Error, CustomStringConvertible {
        case missingCard(String)
        case missingStronghold(String)
        case missingProvince(String)
        case noStrongholdProvince(String)

        public var description: String {
            switch self {
            case .missingCard(let id): return "Card not found: \(id)"
            case .missingStronghold(let id): return "Stronghold card not found: \(id)"
            case .missingProvince(let id): return "Province card not found: \(id)"
            case .noStrongholdProvince(let civ): return "No stronghold province found for \(civ)"
            }
        }
    }

    /// Build a player's starting state from a deck list.
    public static func makePlayer(index: PlayerIndex, deck: DeckList,
                                  cards: [String: Card], rules: Rules) throws -> PlayerState {
        guard let stronghold = cards[deck.strongholdId] else {
            throw SetupError.missingStronghold(deck.strongholdId)
        }
        guard let strongWeak = stronghold.strongWeak else {
            throw SetupError.missingCard("stronghold has no strong/weak resources: \(deck.strongholdId)")
        }

        // Provinces: the 4 outer + the stronghold province (id ends with _provincia
        // or is the stronghold's province variant). We resolve them in order.
        var provinces: [ProvinceInPlay] = []
        var strongholdProvinceAdded = false
        for id in deck.provinceIds {
            guard let card = cards[id] else { throw SetupError.missingProvince(id) }
            provinces.append(ProvinceInPlay(cardId: id,
                                            baseDefense: card.defense ?? 0,
                                            isStronghold: false,
                                            traits: card.traitSet))
        }
        // Stronghold province: we look it up by convention — the deck has a
        // province whose card has defense 7 and the same civilization; we pick
        // the one named "... (Stronghold)" if present, else synthesize from the
        // stronghold card's defense (default 7).
        let strongholdProvince = cards.values.first { c in
            c.type == .province && c.civilization == deck.civilization && c.defense == 7
        } ?? cards.values.first { c in
            c.type == .province && c.civilization == deck.civilization && c.name.contains("Stronghold")
        }
        if let sp = strongholdProvince {
            provinces.append(ProvinceInPlay(cardId: sp.id,
                                            baseDefense: sp.defense ?? 7,
                                            isStronghold: true,
                                            traits: sp.traitSet))
            strongholdProvinceAdded = true
        }
        if !strongholdProvinceAdded {
            throw SetupError.noStrongholdProvince(deck.civilization.label)
        }

        // Starting resources, with strong/weak adjustment.
        var resources: [ResourceInPlay] = []
        for id in deck.startingResourceIds {
            guard let card = cards[id] else { throw SetupError.missingCard(id) }
            let printed = card.production ?? .zero
            let adjusted = Economy.adjustedProduction(printed, strongWeak: strongWeak)
            resources.append(ResourceInPlay(cardId: id,
                                            production: adjusted,
                                            isReady: !card.entersTapped))
        }

        return PlayerState(index: index,
                           civilization: deck.civilization,
                           strongholdCardId: deck.strongholdId,
                           strongWeak: strongWeak,
                           provinces: provinces,
                           resources: resources,
                           empireDeck: deck.empire,
                           tacticsDeck: deck.tactics,
                           empireHand: [],
                           tacticsHand: [])
    }

    /// Build the 5-card destiny map deterministically from the catalog.
    public static func makeDestinyMap(def: DestinyMapDef, cards: [String: Card],
                                      rng: inout RandomSource) throws -> [DestinyInPlay] {
        func pick(_ category: DestinyCategory) throws -> DestinyInPlay {
            let pool = def.pool(for: category)
            guard !pool.isEmpty else {
                throw SetupError.missingCard("no destiny cards for category \(category.rawValue)")
            }
            let chosen = pool[rng.nextInt(pool.count)]
            guard let card = cards[chosen] else {
                throw SetupError.missingCard(chosen)
            }
            return DestinyInPlay(cardId: chosen, category: category, traits: card.traitSet)
        }
        return [
            try pick(.tradeRoute),
            try pick(.naturalTerrain),
            try pick(.militaryPosition),
            try pick(.sacredOrMonument),
            try pick(.waterBorder)
        ]
    }
}
