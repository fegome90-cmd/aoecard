import Foundation

/// A resource card currently in play for a player. Resources tap to pay and
/// untap at the start of the player's round.
public struct ResourceInPlay: Hashable, Sendable {
    public let id: UUID
    public let cardId: String
    /// Effective production, already adjusted for strong/weak resource modifiers.
    public let production: ResourceAmount
    public var isReady: Bool

    public init(id: UUID = UUID(), cardId: String, production: ResourceAmount, isReady: Bool = true) {
        self.id = id
        self.cardId = cardId
        self.production = production
        self.isReady = isReady
    }

    public var producesKind: (food: Bool, wood: Bool, gold: Bool) {
        (production.food > 0, production.wood > 0, production.gold > 0)
    }
}

/// A province in a player's row. `isStronghold` marks the central province.
public struct ProvinceInPlay: Hashable, Sendable {
    public let cardId: String
    public let baseDefense: Int
    public var currentDefense: Int
    public var damage: Int
    public var isBroken: Bool
    public var isStronghold: Bool
    public var traits: Set<Trait>
    /// Buildings attached to this province (modify defense).
    public var buildings: [String]

    public init(cardId: String, baseDefense: Int, isStronghold: Bool = false,
                traits: Set<Trait> = []) {
        self.cardId = cardId
        self.baseDefense = baseDefense
        self.currentDefense = baseDefense
        self.damage = 0
        self.isBroken = false
        self.isStronghold = isStronghold
        self.traits = traits
        self.buildings = []
    }

    /// Apply damage; if damage meets/exceeds currentDefense, the province breaks.
    public mutating func applyDamage(_ amount: Int) {
        guard !isBroken else { return }
        damage += amount
        if damage >= currentDefense {
            isBroken = true
        }
    }
}

/// A unit in play with its current state and effective modifiers.
public struct UnitInPlay: Hashable, Sendable {
    public let id: UUID
    public let cardId: String
    public var civilization: Civilization
    public var traits: Set<Trait>
    public var keywords: KeywordSet
    public var baseStats: Stats
    public var isReady: Bool
    public var damage: Int
    /// Cost paid to play this unit (used by some effects).
    public var costPaid: ResourceAmount
    public var attachedFollowers: [String]

    public init(id: UUID = UUID(), cardId: String, civilization: Civilization,
                traits: Set<Trait>, keywords: KeywordSet, baseStats: Stats,
                isReady: Bool = true, damage: Int = 0,
                costPaid: ResourceAmount = .zero, attachedFollowers: [String] = []) {
        self.id = id
        self.cardId = cardId
        self.civilization = civilization
        self.traits = traits
        self.keywords = keywords
        self.baseStats = baseStats
        self.isReady = isReady
        self.damage = damage
        self.costPaid = costPaid
        self.attachedFollowers = attachedFollowers
    }

    public var isDestroyed: Bool { damage >= baseStats.defense }
}

/// A technology/building/special in play. We track presence rather than
/// detailed state (their effects are applied as modifiers).
public struct PermanentInPlay: Hashable, Sendable {
    public let id: UUID
    public let cardId: String
    public let type: CardType
    public let civilization: Civilization
    public let traits: Set<Trait>

    public init(id: UUID = UUID(), cardId: String, type: CardType,
                civilization: Civilization, traits: Set<Trait>) {
        self.id = id
        self.cardId = cardId
        self.type = type
        self.civilization = civilization
        self.traits = traits
    }
}

/// Index of a player (0 = first / attacker-side for initiative; 1 = second).
public typealias PlayerIndex = Int

/// All mutable state for one player during a game.
public struct PlayerState: Sendable {
    public let index: PlayerIndex
    public let civilization: Civilization
    public var strongholdCardId: String
    public var strongWeak: StrongWeakResources

    public var provinces: [ProvinceInPlay]   // includes the stronghold province
    public var resources: [ResourceInPlay]
    public var units: [UnitInPlay]
    public var permanents: [PermanentInPlay]  // buildings / tech / specials

    public var empireDeck: [String]           // top is last element
    public var tacticsDeck: [String]
    public var empireHand: [String]
    public var tacticsHand: [String]

    /// Whether the stronghold province has been exposed (all outer broken).
    public var strongholdExposed: Bool { provinces.filter { !$0.isStronghold }.allSatisfy { $0.isBroken } }

    public init(index: PlayerIndex, civilization: Civilization,
                strongholdCardId: String, strongWeak: StrongWeakResources,
                provinces: [ProvinceInPlay], resources: [ResourceInPlay],
                units: [UnitInPlay] = [], permanents: [PermanentInPlay] = [],
                empireDeck: [String] = [], tacticsDeck: [String] = [],
                empireHand: [String] = [], tacticsHand: [String] = []) {
        self.index = index
        self.civilization = civilization
        self.strongholdCardId = strongholdCardId
        self.strongWeak = strongWeak
        self.provinces = provinces
        self.resources = resources
        self.units = units
        self.permanents = permanents
        self.empireDeck = empireDeck
        self.tacticsDeck = tacticsDeck
        self.empireHand = empireHand
        self.tacticsHand = tacticsHand
    }

    /// Untap all resources and units (start-of-round ready step).
    ///
    /// `resources[].isReady` invariant (audit AF-02). The tap state of a
    /// resource card has exactly THREE coordinated writer surfaces; touching any
    /// of them without understanding the cycle breaks tap-to-pay:
    ///
    ///   1. **`Economy.commit`** — taps resources (`isReady = false`) to pay for
    ///      a card. This is the only path that consumes readiness.
    ///   2. **`PlayerState.readyAll`** (HERE) — untaps every resource and unit
    ///      at the start of each round. Called by `RulesEngine.play` between rounds.
    ///   3. **`RulesEngine.perform`** — selectively untaps resources as the effect
    ///      of tactics (`untapResources`) and as the reward for a won incursion
    ///      (untap one gold-producing resource). These are intentional exceptions
    ///      to the "only round-reset untaps" rule, scoped to specific effects.
    ///
    /// The engine is single-threaded with value-type state, so there is no race;
    /// the risk is purely structural — a future maintainer adding a fourth writer
    /// (e.g. an effect that taps opponent resources) must preserve the invariant
    /// that every resource tapped by `Economy.commit` is untapped exactly once
    /// per round by `readyAll`, plus at most the documented effect-driven untaps.
    public mutating func readyAll() {
        for i in resources.indices { resources[i].isReady = true }
        for i in units.indices { units[i].isReady = true }
    }

    /// Resources that are currently ready (untapped).
    public var readyResources: [ResourceInPlay] { resources.filter { $0.isReady } }

    /// Draw one card from the empire deck into the hand. Returns the card id, or
    /// nil if the deck is empty.
    public mutating func drawEmpire() -> String? {
        guard let id = empireDeck.popLast() else { return nil }
        empireHand.append(id)
        return id
    }

    public mutating func drawTactics() -> String? {
        guard let id = tacticsDeck.popLast() else { return nil }
        tacticsHand.append(id)
        return id
    }
}
