import Foundation

/// The civilization a card or player belongs to. Neutral cards may be included
/// by any civilization's deck (subject to deck legality).
public enum Civilization: String, Codable, Hashable, Sendable, CaseIterable {
    case mongoles
    case britanos
    case mapuches
    case neutral

    public var label: String {
        switch self {
        case .mongoles: return "Mongoles"
        case .britanos: return "Britanos"
        case .mapuches: return "Mapuches"
        case .neutral: return "Neutral"
        }
    }
}

/// Which of the two decks a card lives in.
public enum DeckSlot: String, Codable, Hashable, Sendable {
    case empire
    case tactics
}

/// Card types (see rules v0.6 §"Tipos de carta").
public enum CardType: String, Codable, Hashable, Sendable {
    case stronghold
    case province
    case resource
    case unit
    case building
    case technology
    case special
    case order
    case maneuver
    case reaction
    case formation
    case follower
    case battlefield
    case destiny

    /// Whether this type belongs to the Empire deck (as opposed to Tactics).
    public var isEmpire: Bool {
        switch self {
        case .resource, .unit, .building, .technology, .special:
            return true
        case .stronghold, .province, .destiny:
            return false // not part of the regular deck pools
        case .order, .maneuver, .reaction, .formation, .follower, .battlefield:
            return false
        }
    }

    public var isTactics: Bool {
        switch self {
        case .order, .maneuver, .reaction, .formation, .follower, .battlefield:
            return true
        default:
            return false
        }
    }
}

/// Categories of the central Destiny map. A v0.6 game reveals exactly one card
/// of each category.
public enum DestinyCategory: String, Codable, Hashable, Sendable {
    case tradeRoute        // Ruta Comercial
    case naturalTerrain    // Terreno Natural
    case militaryPosition  // Posición Militar
    case sacredOrMonument  // Lugar Sagrado o Monumental
    case waterBorder       // Frontera de Agua: Río, Costa, Lago o Humedal
}
