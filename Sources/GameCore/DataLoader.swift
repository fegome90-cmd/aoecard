import Foundation
import Yams

/// Errors surfaced during data loading and validation.
public enum DataError: Error, CustomStringConvertible {
    case fileNotFound(String)
    case readFailed(String, underlying: Error)
    case decodeFailed(String, underlying: Error)
    case locatorFailed(String)
    case malformed(String)

    public var description: String {
        switch self {
        case .fileNotFound(let p): return "File not found: \(p)"
        case .readFailed(let p, let e): return "Failed to read \(p): \(e)"
        case .decodeFailed(let p, let e): return "Failed to decode \(p): \(e)"
        case .locatorFailed(let m): return "Data locator failed: \(m)"
        case .malformed(let m): return "Malformed data: \(m)"
        }
    }
}

/// Resolves the on-disk `Data/` directory.
///
/// Resolution order (first match wins):
///   1. An explicit override (`--data-dir` / `AOE_DATA_DIR` env var).
///   2. Walk up from this source file (`#filePath`) until a directory contains
///      both `Package.swift` and `Data/`. This makes the package relocatable
///      for tests and CLI runs alike.
///   3. The current working directory if it contains `Data/`.
public struct DataLocator: Sendable {
    public let dataDirectory: URL

    /// Optional explicit override passed from the CLI / env.
    public init(override: String? = nil) throws {
        if let override, !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw DataError.locatorFailed("override path does not exist: \(override)")
            }
            self.dataDirectory = url
            return
        }
        if let env = ProcessInfo.processInfo.environment["AOE_DATA_DIR"], !env.isEmpty {
            let url = URL(fileURLWithPath: env)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw DataError.locatorFailed("AOE_DATA_DIR does not exist: \(env)")
            }
            self.dataDirectory = url
            return
        }
        // Walk up from this file until we find Package.swift + Data/.
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        // Sources/GameCore -> Sources -> package root
        let candidate = here
            .deletingLastPathComponent()      // Sources
            .deletingLastPathComponent()      // package root
        let dataDir = candidate.appendingPathComponent("Data")
        if FileManager.default.fileExists(atPath: dataDir.path) {
            self.dataDirectory = dataDir
            return
        }
        // Fallback: current working directory.
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let cwdData = cwd.appendingPathComponent("Data")
        if FileManager.default.fileExists(atPath: cwdData.path) {
            self.dataDirectory = cwdData
            return
        }
        throw DataError.locatorFailed("Could not locate Data/ directory")
    }

    public func url(for relative: String) -> URL {
        dataDirectory.appendingPathComponent(relative)
    }

    public func exists(relative: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: relative).path)
    }
}

/// Reads a YAML or JSON file and decodes it. We parse everything via Yams (YAML
/// is a superset of JSON), then decode through a JSON decoder for typed structs.
public enum FileLoader {
    /// Decode a `Decodable` from a YAML/JSON file at the given URL.
    public static func loadJSON<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DataError.fileNotFound(url.path)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw DataError.readFailed(url.path, underlying: error)
        }
        return try loadJSON(type, from: data, label: url.path)
    }

    /// Decode a `Decodable` from raw YAML/JSON bytes.
    public static func loadJSON<T: Decodable>(_ type: T.Type, from data: Data,
                                               label: String = "<bytes>") throws -> T {
        guard let string = String(data: data, encoding: .utf8) else {
            throw DataError.readFailed(label, underlying: NSError(domain: "FileLoader", code: 1))
        }
        let any: Any?
        do {
            any = try Yams.load(yaml: string, .default)
        } catch {
            throw DataError.decodeFailed(label, underlying: error)
        }
        guard let parsed = any else {
            throw DataError.malformed("Empty or null document at \(label)")
        }
        let json: Data
        do {
            json = try JSONSerialization.data(withJSONObject: parsed, options: [])
        } catch {
            throw DataError.decodeFailed(label, underlying: error)
        }
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: json)
        } catch {
            throw DataError.decodeFailed(label, underlying: error)
        }
    }
}

/// Loads all cards from `cards/*.yaml`, returning them keyed by id.
public struct CardLoader {
    public let locator: DataLocator

    public init(locator: DataLocator) {
        self.locator = locator
    }

    /// Container used for decoding a card file. Each file holds a top-level
    /// `cards: [...]` map (or a bare list, which we accept too).
    private struct CardFile: Decodable {
        let cards: [Card]
    }

    /// Load every `.yaml`/`.yml`/`.json` file directly inside `cards/`.
    public func loadAllCards() throws -> [String: Card] {
        let dir = locator.url(for: "cards")
        var entries: [String: Card] = [:]
        let files = try listFiles(in: dir, extensions: ["yaml", "yml", "json"])
        // Sort for deterministic load order (does not affect RNG, but makes
        // duplicate-id errors reproducible).
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let cf = try FileLoader.loadJSON(CardFile.self, at: file)
            for card in cf.cards {
                if entries[card.id] != nil {
                    throw DataError.malformed("Duplicate card id: \(card.id)")
                }
                entries[card.id] = card
            }
        }
        return entries
    }

    /// Load all decks from `decks/*.yaml` keyed by deck id.
    public func loadAllDecks() throws -> [String: DeckList] {
        let dir = locator.url(for: "decks")
        var entries: [String: DeckList] = [:]
        let files = try listFiles(in: dir, extensions: ["yaml", "yml", "json"])
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let df = try FileLoader.loadJSON(DeckListFile.self, at: file)
            for deck in df.decks {
                if entries[deck.id] != nil {
                    throw DataError.malformed("Duplicate deck id: \(deck.id)")
                }
                entries[deck.id] = deck
            }
        }
        return entries
    }

    /// Load the rules document.
    public func loadRules(filename: String = "rules/rules_v06.yaml") throws -> Rules {
        try FileLoader.loadJSON(Rules.self, at: locator.url(for: filename))
    }

    /// Load the destiny map definition.
    public func loadDestinyMap(filename: String = "maps/destiny_v06.yaml") throws -> DestinyMapDef {
        try FileLoader.loadJSON(DestinyMapDef.self, at: locator.url(for: filename))
    }

    /// Load the strategy catalog.
    public func loadStrategies(filename: String = "strategies/strategies_v06.yaml") throws -> StrategyCatalog {
        try FileLoader.loadJSON(StrategyCatalog.self, at: locator.url(for: filename))
    }

    private func listFiles(in dir: URL, extensions: [String]) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(at: dir,
                                                                includingPropertiesForKeys: nil)
        return urls.filter { extensions.contains($0.pathExtension) }
    }
}

/// A deck list: an id, a civilization, and a flat list of card ids per slot.
public struct DeckList: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var civilization: Civilization
    public var strongholdId: String
    public var provinceIds: [String]
    public var startingResourceIds: [String]
    public var empire: [String]
    public var tactics: [String]

    public init(id: String, name: String, civilization: Civilization,
                strongholdId: String, provinceIds: [String],
                startingResourceIds: [String], empire: [String], tactics: [String]) {
        self.id = id
        self.name = name
        self.civilization = civilization
        self.strongholdId = strongholdId
        self.provinceIds = provinceIds
        self.startingResourceIds = startingResourceIds
        self.empire = empire
        self.tactics = tactics
    }
}

private struct DeckListFile: Decodable { let decks: [DeckList] }

/// Destiny map definition: a pool of destiny card ids grouped by category. The
/// simulator picks one of each category per game, deterministically from seed.
public struct DestinyMapDef: Codable, Hashable, Sendable {
    public var tradeRoutes: [String]
    public var naturalTerrains: [String]
    public var militaryPositions: [String]
    public var sacredOrMonuments: [String]
    public var waterBorders: [String]

    public init(tradeRoutes: [String] = [], naturalTerrains: [String] = [],
                militaryPositions: [String] = [], sacredOrMonuments: [String] = [],
                waterBorders: [String] = []) {
        self.tradeRoutes = tradeRoutes
        self.naturalTerrains = naturalTerrains
        self.militaryPositions = militaryPositions
        self.sacredOrMonuments = sacredOrMonuments
        self.waterBorders = waterBorders
    }

    public func pool(for category: DestinyCategory) -> [String] {
        switch category {
        case .tradeRoute: return tradeRoutes
        case .naturalTerrain: return naturalTerrains
        case .militaryPosition: return militaryPositions
        case .sacredOrMonument: return sacredOrMonuments
        case .waterBorder: return waterBorders
        }
    }
}

/// A strategy in the catalog. Priorities are decision weights in `[0, 1]`.
public struct Strategy: Codable, Hashable, Sendable {
    public var name: String
    public var civilization: Civilization
    public var priorities: Priorities

    public init(name: String, civilization: Civilization, priorities: Priorities) {
        self.name = name
        self.civilization = civilization
        self.priorities = priorities
    }

    public struct Priorities: Codable, Hashable, Sendable {
        public var playResource: Double
        public var playUnit: Double
        public var playBuilding: Double
        public var attackProvince: Double
        public var attackDestiny: Double
        public var incursion: Double
        public var assault: Double
        public var defend: Double
        public var holdTactics: Double
        public var buildWonder: Double

        public init(playResource: Double = 0.5, playUnit: Double = 0.5,
                    playBuilding: Double = 0.3, attackProvince: Double = 0.4,
                    attackDestiny: Double = 0.6, incursion: Double = 0.5,
                    assault: Double = 0.4, defend: Double = 0.5,
                    holdTactics: Double = 0.5, buildWonder: Double = 0.1) {
            self.playResource = playResource
            self.playUnit = playUnit
            self.playBuilding = playBuilding
            self.attackProvince = attackProvince
            self.attackDestiny = attackDestiny
            self.incursion = incursion
            self.assault = assault
            self.defend = defend
            self.holdTactics = holdTactics
            self.buildWonder = buildWonder
        }
    }
}

public struct StrategyCatalog: Codable, Hashable, Sendable {
    public var strategies: [Strategy]
    public init(strategies: [Strategy] = []) { self.strategies = strategies }
}
