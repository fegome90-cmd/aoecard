import Foundation

/// Combat stats for a unit card (and other cards that may participate).
public struct Stats: Codable, Hashable, Sendable {
    public var attack: Int
    public var defense: Int
    public var range: Int

    public init(attack: Int = 0, defense: Int = 0, range: Int = 0) {
        self.attack = attack
        self.defense = defense
        self.range = range
    }

    private enum CodingKeys: String, CodingKey { case attack, defense, range }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        attack = try c.decodeIfPresent(Int.self, forKey: .attack) ?? 0
        defense = try c.decodeIfPresent(Int.self, forKey: .defense) ?? 0
        range = try c.decodeIfPresent(Int.self, forKey: .range) ?? 0
    }
}

/// Cost to play a card. Components are non-negative requirements per resource.
public typealias Cost = ResourceAmount

/// Production printed on a Resource card.
public typealias Production = ResourceAmount

/// An ability printed on a card. Abilities may declare discrete effects by id,
/// or only carry human-readable text (in which case `effects` is empty).
public struct Ability: Codable, Hashable, Sendable {
    public enum Timing: String, Codable, Hashable, Sendable {
        case battle
        case action
        case reaction
        case passive
        case roundStart
        case roundEnd
    }

    public var timing: Timing
    public var name: String
    public var text: String
    public var effects: [Effect]

    public init(timing: Timing, name: String, text: String = "", effects: [Effect] = []) {
        self.timing = timing
        self.name = name
        self.text = text
        self.effects = effects
    }

    private enum CodingKeys: String, CodingKey { case timing, name, text, effects }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        timing = try c.decodeIfPresent(Timing.self, forKey: .timing) ?? .action
        name = try c.decode(String.self, forKey: .name)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        effects = try c.decodeIfPresent([Effect].self, forKey: .effects) ?? []
    }
}

/// Construction and in-play limits. Note that `uniqueInPlay` (table rule) and
/// `maxCopiesInDeck` (deckbuilding rule) are independent fields. A card with
/// `uniqueInPlay: true` does NOT automatically imply a deck copy limit.
public struct CardLimits: Codable, Hashable, Sendable {
    /// Table rule: only one copy of this card may be in play at a time.
    public var uniqueInPlay: Bool
    /// Deckbuilding rule: maximum copies of this card allowed in a deck.
    /// `nil` means "no per-card limit declared" (no implicit cap).
    public var maxCopiesInDeck: Int?

    public init(uniqueInPlay: Bool = false, maxCopiesInDeck: Int? = nil) {
        self.uniqueInPlay = uniqueInPlay
        self.maxCopiesInDeck = maxCopiesInDeck
    }

    private enum CodingKeys: String, CodingKey { case uniqueInPlay, maxCopiesInDeck }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uniqueInPlay = try c.decodeIfPresent(Bool.self, forKey: .uniqueInPlay) ?? false
        maxCopiesInDeck = try c.decodeIfPresent(Int.self, forKey: .maxCopiesInDeck)
    }
}

/// Balance metadata for the author. Not enforced by the engine; surfaced in
/// reports.
public struct CardBalance: Codable, Hashable, Sendable {
    public enum Status: String, Codable, Hashable, Sendable {
        case stable, watch, buff, nerf, banned
    }

    public var status: Status
    public var notes: String

    public init(status: Status = .stable, notes: String = "") {
        self.status = status
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey { case status, notes }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decodeIfPresent(Status.self, forKey: .status) ?? .stable
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }
}

/// A complete card definition, decoded from YAML.
public struct Card: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var civilization: Civilization
    public var deck: DeckSlot?
    public var type: CardType
    public var traits: [Trait]
    public var cost: Cost
    public var production: Production?
    public var stats: Stats?
    public var defense: Int?           // provinces / strongholds: defense value
    public var keywords: [Keyword]
    public var abilities: [Ability]
    public var effects: [Effect]       // top-level effects (e.g. tactics)
    public var limits: CardLimits
    public var balance: CardBalance
    /// Human-readable reminder text; ignored by the engine.
    public var text: [String]
    /// Strong/weak resource pair (strongholds only).
    public var strongWeak: StrongWeakResources?
    /// Whether this resource enters the board tapped.
    public var entersTapped: Bool
    /// Destiny category (destiny cards only).
    public var destinyCategory: DestinyCategory?

    public init(id: String,
                name: String,
                civilization: Civilization,
                deck: DeckSlot? = nil,
                type: CardType,
                traits: [Trait] = [],
                cost: Cost = .zero,
                production: Production? = nil,
                stats: Stats? = nil,
                defense: Int? = nil,
                keywords: [Keyword] = [],
                abilities: [Ability] = [],
                effects: [Effect] = [],
                limits: CardLimits = .init(),
                balance: CardBalance = .init(),
                text: [String] = [],
                strongWeak: StrongWeakResources? = nil,
                entersTapped: Bool = false,
                destinyCategory: DestinyCategory? = nil) {
        self.id = id
        self.name = name
        self.civilization = civilization
        self.deck = deck
        self.type = type
        self.traits = traits
        self.cost = cost
        self.production = production
        self.stats = stats
        self.defense = defense
        self.keywords = keywords
        self.abilities = abilities
        self.effects = effects
        self.limits = limits
        self.balance = balance
        self.text = text
        self.strongWeak = strongWeak
        self.entersTapped = entersTapped
        self.destinyCategory = destinyCategory
    }

    /// Trait set convenience accessor.
    public var traitSet: Set<Trait> { Set(traits) }

    /// Convenience: keyword view.
    public var keywordSet: KeywordSet { KeywordSet(entries: keywords) }
}

extension Card {
    private enum CodingKeys: String, CodingKey {
        case id, name, civilization, deck, type, traits, cost, production
        case stats, defense, keywords, abilities, effects, limits, balance
        case text, strongWeak, entersTapped, destinyCategory
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        civilization = try c.decode(Civilization.self, forKey: .civilization)
        deck = try c.decodeIfPresent(DeckSlot.self, forKey: .deck)
        type = try c.decode(CardType.self, forKey: .type)
        traits = try c.decodeIfPresent([Trait].self, forKey: .traits) ?? []
        cost = try c.decodeIfPresent(Cost.self, forKey: .cost) ?? .zero
        production = try c.decodeIfPresent(Production.self, forKey: .production)
        stats = try c.decodeIfPresent(Stats.self, forKey: .stats)
        defense = try c.decodeIfPresent(Int.self, forKey: .defense)
        keywords = try c.decodeIfPresent([Keyword].self, forKey: .keywords) ?? []
        abilities = try c.decodeIfPresent([Ability].self, forKey: .abilities) ?? []
        effects = try c.decodeIfPresent([Effect].self, forKey: .effects) ?? []
        limits = try c.decodeIfPresent(CardLimits.self, forKey: .limits) ?? .init()
        balance = try c.decodeIfPresent(CardBalance.self, forKey: .balance) ?? .init()
        text = try c.decodeIfPresent([String].self, forKey: .text) ?? []
        strongWeak = try c.decodeIfPresent(StrongWeakResources.self, forKey: .strongWeak)
        entersTapped = try c.decodeIfPresent(Bool.self, forKey: .entersTapped) ?? false
        destinyCategory = try c.decodeIfPresent(DestinyCategory.self, forKey: .destinyCategory)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(civilization, forKey: .civilization)
        try c.encodeIfPresent(deck, forKey: .deck)
        try c.encode(type, forKey: .type)
        if !traits.isEmpty { try c.encode(traits, forKey: .traits) }
        if !cost.isFree { try c.encode(cost, forKey: .cost) }
        try c.encodeIfPresent(production, forKey: .production)
        try c.encodeIfPresent(stats, forKey: .stats)
        try c.encodeIfPresent(defense, forKey: .defense)
        if !keywords.isEmpty { try c.encode(keywords, forKey: .keywords) }
        if !abilities.isEmpty { try c.encode(abilities, forKey: .abilities) }
        if !effects.isEmpty { try c.encode(effects, forKey: .effects) }
        try c.encode(limits, forKey: .limits)
        try c.encode(balance, forKey: .balance)
        if !text.isEmpty { try c.encode(text, forKey: .text) }
        try c.encodeIfPresent(strongWeak, forKey: .strongWeak)
        if entersTapped { try c.encode(entersTapped, forKey: .entersTapped) }
        try c.encodeIfPresent(destinyCategory, forKey: .destinyCategory)
    }
}
