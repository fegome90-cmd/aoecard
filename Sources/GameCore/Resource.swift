import Foundation

/// The three spendable resources in Age of Provinces.
public enum ResourceKind: String, Codable, Hashable, Sendable, CaseIterable {
    case food
    case wood
    case gold

    /// Display-friendly short label used by CLI/CSV output.
    public var label: String { rawValue }
}

/// A cost to pay or an amount produced, across the three resource kinds.
///
/// Resources never float in a pool: production is spent immediately by tapping
/// the producing card. Any surplus produced beyond what was needed is wasted
/// (tracked in `resources_wasted_*`).
public struct ResourceAmount: Codable, Hashable, Sendable {
    public var food: Int
    public var wood: Int
    public var gold: Int

    public init(food: Int = 0, wood: Int = 0, gold: Int = 0) {
        self.food = food
        self.wood = wood
        self.gold = gold
    }

    /// Zero cost / zero production.
    public static let zero = ResourceAmount()

    public func get(_ kind: ResourceKind) -> Int {
        switch kind {
        case .food: return food
        case .wood: return wood
        case .gold: return gold
        }
    }

    public mutating func set(_ kind: ResourceKind, _ value: Int) {
        switch kind {
        case .food: food = value
        case .wood: wood = value
        case .gold: gold = value
        }
    }

    /// True when every component is <= 0 (no positive requirement anywhere).
    public var isFree: Bool { food <= 0 && wood <= 0 && gold <= 0 }

    /// Sum across all three kinds.
    public var total: Int { food + wood + gold }

    /// Component-wise addition.
    public static func + (lhs: ResourceAmount, rhs: ResourceAmount) -> ResourceAmount {
        ResourceAmount(food: lhs.food + rhs.food,
                       wood: lhs.wood + rhs.wood,
                       gold: lhs.gold + rhs.gold)
    }

    /// Component-wise subtraction (components may go negative).
    public static func - (lhs: ResourceAmount, rhs: ResourceAmount) -> ResourceAmount {
        ResourceAmount(food: lhs.food - rhs.food,
                       wood: lhs.wood - rhs.wood,
                       gold: lhs.gold - rhs.gold)
    }

    /// Compound assignment, enabling `total += other` (component-wise add).
    public static func += (lhs: inout ResourceAmount, rhs: ResourceAmount) {
        lhs = lhs + rhs
    }

    /// Compound assignment, enabling `total -= other` (component-wise sub).
    public static func -= (lhs: inout ResourceAmount, rhs: ResourceAmount) {
        lhs = lhs - rhs
    }

    /// Clamps all components to >= 0. Used when a weak-resource penalty would
    /// push production below zero.
    public func clampedToNonNegative() -> ResourceAmount {
        ResourceAmount(food: max(0, food),
                       wood: max(0, wood),
                       gold: max(0, gold))
    }
}

extension ResourceAmount {
    private enum CodingKeys: String, CodingKey { case food, wood, gold }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        food = try container.decodeIfPresent(Int.self, forKey: .food) ?? 0
        wood = try container.decodeIfPresent(Int.self, forKey: .wood) ?? 0
        gold = try container.decodeIfPresent(Int.self, forKey: .gold) ?? 0
    }
}

/// Strong / weak resource pair for a civilization's stronghold.
public struct StrongWeakResources: Codable, Hashable, Sendable {
    public var strong: ResourceKind
    public var weak: ResourceKind

    public init(strong: ResourceKind, weak: ResourceKind) {
        self.strong = strong
        self.weak = weak
    }
}
