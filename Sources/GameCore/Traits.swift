import Foundation

/// All traits used in v0.6. Traits mark civilization, unit role, terrain, and
/// special status; they are referenced by keyword filters, effect filters, and
/// terrain modifiers.
public enum Trait: String, Codable, Hashable, Sendable {
    // Civilizations
    case mongoles
    case britanos
    case mapuches
    case neutral

    // Unit roles
    case infanteria        // Infantería
    case arqueria          // Arquería
    case caballeria        // Caballería
    case caballeriaArquera // Caballería Arquera
    case lancero           // Lancero
    case asedio            // Asedio
    case naval             // Naval
    case monje             // Monje
    case anfibio           // Anfibio (also a keyword; kept as trait for filtering)

    case explorador        // Explorador
    case guardia           // Guardia
    case lider             // Líder
    case campeon           // Campeón
    case ingeniero         // Ingeniero
    case aldeano           // Aldeano
    case mercenario        // Mercenario

    case unica             // Única (status)
    case veterano          // Veterano
    case elite             // Élite
    case imperial          // Imperial

    // Terrains (used by Province/Destiny traits and keyword conditions)
    case bosque            // Bosque
    case llanura           // Llanura
    case rutaComercial     // Ruta Comercial
    case costa             // Costa
    case rio               // Río
    case lago              // Lago
    case humedal           // Humedal
    case paso              // Paso
    case monasterio        // Monasterio
    case mina              // Mina
    case granja            // Granja
    case colina            // Colina (extra terrain used by Britanos/destinies)
}

extension Trait {
    /// Traits that designate a water terrain (relevant for Anfibio, Naval,
    /// and several Mongol/Mapuche effects).
    public static let waterTerrains: Set<Trait> = [.rio, .costa, .lago, .humedal]

    /// Defensive terrains referenced by stronghold abilities and tactics.
    public static let restrictiveTerrains: Set<Trait> = [.bosque, .humedal, .paso]
}

/// A type-erased matcher over a set of traits, used by effect and keyword
/// filters ("target_filter", "trait_filter").
public struct TraitFilter: Codable, Hashable, Sendable {
    /// Match cards that have ALL of these traits (empty = match all).
    public var requireAll: [Trait]
    /// Match cards that have ANY of these traits (empty = ignored).
    public var requireAny: [Trait]
    /// Match cards that have NONE of these traits.
    public var requireNone: [Trait]

    public init(requireAll: [Trait] = [],
                requireAny: [Trait] = [],
                requireNone: [Trait] = []) {
        self.requireAll = requireAll
        self.requireAny = requireAny
        self.requireNone = requireNone
    }

    /// Match-all wildcard.
    public static let any = TraitFilter()

    public func matches(_ traits: Set<Trait>) -> Bool {
        if !requireAll.isEmpty {
            for t in requireAll where !traits.contains(t) { return false }
        }
        if !requireAny.isEmpty {
            let anyMatched = requireAny.contains { traits.contains($0) }
            if !anyMatched { return false }
        }
        if !requireNone.isEmpty {
            for t in requireNone where traits.contains(t) { return false }
        }
        return true
    }
}

extension TraitFilter {
    private enum CodingKeys: String, CodingKey {
        case requireAll, requireAny, requireNone
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            requireAll: try c.decodeIfPresent([Trait].self, forKey: .requireAll) ?? [],
            requireAny: try c.decodeIfPresent([Trait].self, forKey: .requireAny) ?? [],
            requireNone: try c.decodeIfPresent([Trait].self, forKey: .requireNone) ?? []
        )
    }
}
