import Foundation

/// Battle keywords recognized by the engine. Keywords may carry a magnitude
/// (Carga X, Anti-Caballería X, Asedio X, Conversión X, Reparar X, Guarnecer X).
public enum KeywordName: String, Codable, Hashable, Sendable {
    case anfibio           // Anfibio
    case contraataque      // Contraataque
    case hostigar          // Hostigar
    case alcanceSuperior   // Alcance Superior
    case iniciativa        // Iniciativa
    case carga             // Carga X
    case antiCaballeria    // Anti-Caballería X
    case asedio            // Asedio X
    case mando             // Mando
    case conversion        // Conversión X
    case reparar           // Reparar X
    case guarnecer         // Guarnecer X
    case unica             // Única (as a keyword on units)
}

/// A keyword entry on a card. `magnitude` is only meaningful for keywords that
/// carry an X value.
public struct Keyword: Codable, Hashable, Sendable {
    public var name: KeywordName
    public var magnitude: Int

    public init(name: KeywordName, magnitude: Int = 0) {
        self.name = name
        self.magnitude = magnitude
    }

    private enum CodingKeys: String, CodingKey { case name, magnitude }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(KeywordName.self, forKey: .name)
        magnitude = try c.decodeIfPresent(Int.self, forKey: .magnitude) ?? 0
    }
}

extension KeywordName {
    /// Whether this keyword is parameterized by a magnitude.
    public var hasMagnitude: Bool {
        switch self {
        case .carga, .antiCaballeria, .asedio, .conversion, .reparar, .guarnecer:
            return true
        case .anfibio, .contraataque, .hostigar, .alcanceSuperior,
             .iniciativa, .mando, .unica:
            return false
        }
    }
}

/// A typed view over a unit's keywords, used by the combat resolver to look up
/// magnitudes safely.
public struct KeywordSet: Codable, Hashable, Sendable {
    public var entries: [Keyword]

    public init(entries: [Keyword] = []) {
        self.entries = entries
    }

    public func has(_ name: KeywordName) -> Bool {
        entries.contains { $0.name == name }
    }

    public func magnitude(of name: KeywordName) -> Int {
        entries.first { $0.name == name }?.magnitude ?? 0
    }
}
