import Foundation

/// Discrete, machine-resolvable effects. Tactics (and any discrete abilities)
/// declare effects by `id`; the engine resolves effects by enum case, never by
/// card name. See README "Effect vocabulary" for the canonical list.
///
/// The `id` strings used in YAML are snake_case (the canonical form). We keep
/// a separate registry mapping those to enum cases so the case names can stay
/// Swift-idiomatic.
public enum EffectID: String, Codable, Hashable, Sendable {
    case cancelCharge
    case suppressKeyword
    case battleAttackBonus
    case battleDefenseBonus
    case commandAttackBonus
    case provinceDefenseReduction
    case rangeBonus
    case archerBonusVsTrait
    case amphibFirstAttackerBonus
    case untapUnits
    case untapResources
    case grantGarrison
    case freeIncursion
    case revealTacticsTop
    case genericModifier

    /// The snake_case id used in YAML files.
    public var id: String {
        switch self {
        case .cancelCharge:                 return "cancel_charge"
        case .suppressKeyword:              return "suppress_keyword"
        case .battleAttackBonus:            return "battle_attack_bonus"
        case .battleDefenseBonus:           return "battle_defense_bonus"
        case .commandAttackBonus:           return "command_attack_bonus"
        case .provinceDefenseReduction:     return "province_defense_reduction"
        case .rangeBonus:                   return "range_bonus"
        case .archerBonusVsTrait:           return "archer_bonus_vs_trait"
        case .amphibFirstAttackerBonus:     return "amphib_first_attacker_bonus"
        case .untapUnits:                   return "untap_units"
        case .untapResources:               return "untap_resources"
        case .grantGarrison:                return "grant_garrison"
        case .freeIncursion:                return "free_incursion"
        case .revealTacticsTop:             return "reveal_tactics_top"
        case .genericModifier:              return "generic_modifier"
        }
    }

    /// Canonical registry of id strings → cases.
    public static let allByID: [String: EffectID] = Dictionary(
        uniqueKeysWithValues: EffectID.allCases.map { ($0.id, $0) }
    )

    public init?(id: String) {
        guard let v = Self.allByID[id] else { return nil }
        self = v
    }

    // String-based Codable so YAML can use the snake_case id directly.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let v = EffectID(id: raw) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unknown effect id: \(raw)"
            ))
        }
        self = v
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(id)
    }
}

extension EffectID: CaseIterable {}

/// A filter for "what does this effect target". Used both for units and for
/// resources (resource filters use an empty traits set + an optional
/// ResourceKind requirement).
public struct EffectTargetFilter: Codable, Hashable, Sendable {
    public var traits: TraitFilter
    /// When set, restricts to resources producing this kind (for untap effects).
    public var producesResource: ResourceKind?
    /// Restrict to attacking/defending side in a battle context.
    public var side: BattleSide?

    public init(traits: TraitFilter = .any,
                producesResource: ResourceKind? = nil,
                side: BattleSide? = nil) {
        self.traits = traits
        self.producesResource = producesResource
        self.side = side
    }
}

public enum BattleSide: String, Codable, Hashable, Sendable {
    case attacker
    case defender
}

/// A resolved effect with its parameters, decoded from a YAML entry like:
///     - id: battle_attack_bonus
///       amount: 2
///       target_filter:
///         require_any: [caballeria, caballeriaArquera]
public enum Effect: Codable, Hashable, Sendable {
    // No-param effects
    case cancelCharge

    // Single-magnitude effects
    case battleAttackBonus(amount: Int, target: EffectTargetFilter)
    case battleDefenseBonus(amount: Int, target: EffectTargetFilter)
    case commandAttackBonus(amount: Int, traitFilter: TraitFilter)
    case provinceDefenseReduction(amount: Int, condition: TraitFilter)
    case rangeBonus(amount: Int, target: EffectTargetFilter)
    case archerBonusVsTrait(amount: Int, trait: Trait)
    case amphibFirstAttackerBonus(amount: Int)
    case grantGarrison(amount: Int, target: EffectTargetFilter)
    case revealTacticsTop(count: Int)

    // Count + filter effects
    case untapUnits(count: Int, filter: EffectTargetFilter)
    case untapResources(count: Int, produces: ResourceKind?)

    // Keyword suppression
    case suppressKeyword(keyword: KeywordName, terrain: Trait?)

    // High-level actions
    case freeIncursion(targetFilter: TraitFilter)

    // Fallback: tactic whose precise mechanic is not modeled yet.
    case genericModifier(notes: String)

    public var id: EffectID {
        switch self {
        case .cancelCharge:                    return .cancelCharge
        case .battleAttackBonus:               return .battleAttackBonus
        case .battleDefenseBonus:              return .battleDefenseBonus
        case .commandAttackBonus:              return .commandAttackBonus
        case .provinceDefenseReduction:        return .provinceDefenseReduction
        case .rangeBonus:                      return .rangeBonus
        case .archerBonusVsTrait:              return .archerBonusVsTrait
        case .amphibFirstAttackerBonus:        return .amphibFirstAttackerBonus
        case .grantGarrison:                   return .grantGarrison
        case .revealTacticsTop:                return .revealTacticsTop
        case .untapUnits:                      return .untapUnits
        case .untapResources:                  return .untapResources
        case .suppressKeyword:                 return .suppressKeyword
        case .freeIncursion:                   return .freeIncursion
        case .genericModifier:                 return .genericModifier
        }
    }
}

extension Effect {
    private enum CodingKeys: String, CodingKey {
        case id, amount, count, keyword, terrain, trait
        case targetFilter, traitFilter, condition, produces, side, notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(EffectID.self, forKey: .id)
        switch id {
        case .cancelCharge:
            self = .cancelCharge
        case .battleAttackBonus:
            let amount = try c.decodeIfPresent(Int.self, forKey: .amount) ?? 0
            let target = try c.decodeIfPresent(EffectTargetFilter.self, forKey: .targetFilter) ?? .init()
            self = .battleAttackBonus(amount: amount, target: target)
        case .battleDefenseBonus:
            let amount = try c.decodeIfPresent(Int.self, forKey: .amount) ?? 0
            let target = try c.decodeIfPresent(EffectTargetFilter.self, forKey: .targetFilter) ?? .init()
            self = .battleDefenseBonus(amount: amount, target: target)
        case .commandAttackBonus:
            let amount = try c.decodeIfPresent(Int.self, forKey: .amount) ?? 0
            let tf = try c.decodeIfPresent(TraitFilter.self, forKey: .traitFilter) ?? .any
            self = .commandAttackBonus(amount: amount, traitFilter: tf)
        case .provinceDefenseReduction:
            let amount = try c.decodeIfPresent(Int.self, forKey: .amount) ?? 0
            let cond = try c.decodeIfPresent(TraitFilter.self, forKey: .condition) ?? .any
            self = .provinceDefenseReduction(amount: amount, condition: cond)
        case .rangeBonus:
            let amount = try c.decodeIfPresent(Int.self, forKey: .amount) ?? 0
            let target = try c.decodeIfPresent(EffectTargetFilter.self, forKey: .targetFilter) ?? .init()
            self = .rangeBonus(amount: amount, target: target)
        case .archerBonusVsTrait:
            let amount = try c.decodeIfPresent(Int.self, forKey: .amount) ?? 0
            let trait = try c.decode(Trait.self, forKey: .trait)
            self = .archerBonusVsTrait(amount: amount, trait: trait)
        case .amphibFirstAttackerBonus:
            let amount = try c.decodeIfPresent(Int.self, forKey: .amount) ?? 0
            self = .amphibFirstAttackerBonus(amount: amount)
        case .grantGarrison:
            let amount = try c.decodeIfPresent(Int.self, forKey: .amount) ?? 0
            let target = try c.decodeIfPresent(EffectTargetFilter.self, forKey: .targetFilter) ?? .init()
            self = .grantGarrison(amount: amount, target: target)
        case .revealTacticsTop:
            let count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 1
            self = .revealTacticsTop(count: count)
        case .untapUnits:
            let count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 1
            let f = try c.decodeIfPresent(EffectTargetFilter.self, forKey: .targetFilter) ?? .init()
            self = .untapUnits(count: count, filter: f)
        case .untapResources:
            let count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 1
            let produces = try c.decodeIfPresent(ResourceKind.self, forKey: .produces)
            self = .untapResources(count: count, produces: produces)
        case .suppressKeyword:
            let kw = try c.decode(KeywordName.self, forKey: .keyword)
            let terrain = try c.decodeIfPresent(Trait.self, forKey: .terrain)
            self = .suppressKeyword(keyword: kw, terrain: terrain)
        case .freeIncursion:
            let tf = try c.decodeIfPresent(TraitFilter.self, forKey: .targetFilter) ?? .any
            self = .freeIncursion(targetFilter: tf)
        case .genericModifier:
            let notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
            self = .genericModifier(notes: notes)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        switch self {
        case .cancelCharge:
            break
        case .battleAttackBonus(let amount, let target):
            try c.encode(amount, forKey: .amount)
            try c.encode(target, forKey: .targetFilter)
        case .battleDefenseBonus(let amount, let target):
            try c.encode(amount, forKey: .amount)
            try c.encode(target, forKey: .targetFilter)
        case .commandAttackBonus(let amount, let tf):
            try c.encode(amount, forKey: .amount)
            try c.encode(tf, forKey: .traitFilter)
        case .provinceDefenseReduction(let amount, let cond):
            try c.encode(amount, forKey: .amount)
            try c.encode(cond, forKey: .condition)
        case .rangeBonus(let amount, let target):
            try c.encode(amount, forKey: .amount)
            try c.encode(target, forKey: .targetFilter)
        case .archerBonusVsTrait(let amount, let trait):
            try c.encode(amount, forKey: .amount)
            try c.encode(trait, forKey: .trait)
        case .amphibFirstAttackerBonus(let amount):
            try c.encode(amount, forKey: .amount)
        case .grantGarrison(let amount, let target):
            try c.encode(amount, forKey: .amount)
            try c.encode(target, forKey: .targetFilter)
        case .revealTacticsTop(let count):
            try c.encode(count, forKey: .count)
        case .untapUnits(let count, let f):
            try c.encode(count, forKey: .count)
            try c.encode(f, forKey: .targetFilter)
        case .untapResources(let count, let produces):
            try c.encode(count, forKey: .count)
            try c.encodeIfPresent(produces, forKey: .produces)
        case .suppressKeyword(let kw, let terrain):
            try c.encode(kw, forKey: .keyword)
            try c.encodeIfPresent(terrain, forKey: .terrain)
        case .freeIncursion(let tf):
            try c.encode(tf, forKey: .targetFilter)
        case .genericModifier(let notes):
            try c.encode(notes, forKey: .notes)
        }
    }
}

extension EffectTargetFilter {
    private enum CodingKeys: String, CodingKey {
        case requireAll, requireAny, requireNone, produces, side
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let tf = TraitFilter(
            requireAll: try c.decodeIfPresent([Trait].self, forKey: .requireAll) ?? [],
            requireAny: try c.decodeIfPresent([Trait].self, forKey: .requireAny) ?? [],
            requireNone: try c.decodeIfPresent([Trait].self, forKey: .requireNone) ?? []
        )
        let produces = try c.decodeIfPresent(ResourceKind.self, forKey: .produces)
        let side = try c.decodeIfPresent(BattleSide.self, forKey: .side)
        self.init(traits: tf, producesResource: produces, side: side)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if !traits.requireAll.isEmpty { try c.encode(traits.requireAll, forKey: .requireAll) }
        if !traits.requireAny.isEmpty { try c.encode(traits.requireAny, forKey: .requireAny) }
        if !traits.requireNone.isEmpty { try c.encode(traits.requireNone, forKey: .requireNone) }
        try c.encodeIfPresent(producesResource, forKey: .produces)
        try c.encodeIfPresent(side, forKey: .side)
    }
}
