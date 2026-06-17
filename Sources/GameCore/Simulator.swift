import Foundation

/// Runs many games for one or more matchups. Deterministic given the seed:
/// game `i` uses seed `baseSeed + i`.
public struct Simulator {
    public let cards: [String: Card]
    public let rules: Rules
    public let decks: [String: DeckList]
    public let strategies: [Strategy]
    public let destinyDef: DestinyMapDef

    public init(cards: [String: Card], rules: Rules, decks: [String: DeckList],
                strategies: [Strategy], destinyDef: DestinyMapDef) {
        self.cards = cards
        self.rules = rules
        self.decks = decks
        self.strategies = strategies
        self.destinyDef = destinyDef
    }

    // MARK: - Single matchup

    /// Simulate `games` matches of strategyA (deckA) vs strategyB (deckB),
    /// deterministically seeded from `baseSeed`. Game `i` uses seed `baseSeed + i`.
    public func simulate(deckA: DeckList, strategyA: Strategy,
                         deckB: DeckList, strategyB: Strategy,
                         games: Int, baseSeed: UInt64) -> [GameResult] {
        var results: [GameResult] = []
        results.reserveCapacity(games)
        for i in 0..<games {
            let seed = baseSeed &+ UInt64(i)
            let result = playOne(deckA: deckA, strategyA: strategyA,
                                 deckB: deckB, strategyB: strategyB,
                                 seed: seed)
            results.append(result)
        }
        return results
    }

    /// Play one match. Seed fully determines the game.
    public func playOne(deckA: DeckList, strategyA: Strategy,
                        deckB: DeckList, strategyB: Strategy,
                        seed: UInt64) -> GameResult {
        var setupRng = RandomSource(seed: seed)
        guard let playerA = try? GameSetup.makePlayer(index: 0, deck: deckA,
                                                       cards: cards, rules: rules),
              let playerB = try? GameSetup.makePlayer(index: 1, deck: deckB,
                                                       cards: cards, rules: rules),
              let destiny = try? GameSetup.makeDestinyMap(def: destinyDef,
                                                          cards: cards, rng: &setupRng) else {
            // Setup failure → recorded as a stall with seed.
            return GameResult(matchup: "\(deckA.civilization.label) vs \(deckB.civilization.label)",
                              civilizationA: deckA.civilization,
                              civilizationB: deckB.civilization,
                              strategyA: strategyA.name, strategyB: strategyB.name,
                              winner: nil, winCondition: .stall, rounds: 0,
                              firstPlayer: 0, seed: seed)
        }
        // First player determined deterministically by a draw from the same rng.
        let firstPlayer: PlayerIndex = setupRng.nextBool(probability: 0.5) ? 0 : 1
        let state = GameState(players: [playerA, playerB],
                              destinyMap: destiny,
                              round: 1, current: firstPlayer,
                              rng: setupRng, rules: rules, cardsById: cards)
        let engine = RulesEngine(strategyA: strategyA, strategyB: strategyB,
                                 firstPlayer: firstPlayer)
        let (result, _) = engine.play(initialState: state)
        return result
    }

    // MARK: - Matrix

    public enum MatrixMode: String, Sendable {
        case civ       // all civ-vs-civ pairings (each civ uses its default strategy)
        case strategy  // all strategy-vs-strategy pairings (within + across civs)
        case mirror    // each strategy vs itself
    }

    /// Run a matrix of matchups. For `mode == .strategy`, every (sA, sB) ordered
    /// pair is run with the corresponding civ decks. For `mode == .civ`, the
    /// 3 civ-vs-civ pairings use each civ's first strategy. For `mode == .mirror`,
    /// each strategy plays itself.
    public func runMatrix(mode: MatrixMode, gamesPerCell: Int,
                          baseSeed: UInt64) -> [(cell: String, results: [GameResult])] {
        switch mode {
        case .civ:
            return civMatrix(gamesPerCell: gamesPerCell, baseSeed: baseSeed)
        case .strategy:
            return strategyMatrix(gamesPerCell: gamesPerCell, baseSeed: baseSeed)
        case .mirror:
            return mirrorMatrix(gamesPerCell: gamesPerCell, baseSeed: baseSeed)
        }
    }

    private func civMatrix(gamesPerCell: Int, baseSeed: UInt64) -> [(String, [GameResult])] {
        let civOrder: [Civilization] = [.mongoles, .britanos, .mapuches]
        var out: [(String, [GameResult])] = []
        for civA in civOrder {
            for civB in civOrder {
                let cell = "\(civA.label) vs \(civB.label)"
                guard let deckA = deck(for: civA), let deckB = deck(for: civB),
                      let sA = strategies.first(where: { $0.civilization == civA }),
                      let sB = strategies.first(where: { $0.civilization == civB }) else { continue }
                let cellSeed = baseSeed &+ hash(cell)
                let results = simulate(deckA: deckA, strategyA: sA,
                                       deckB: deckB, strategyB: sB,
                                       games: gamesPerCell, baseSeed: cellSeed)
                out.append((cell, results))
            }
        }
        return out
    }

    private func strategyMatrix(gamesPerCell: Int, baseSeed: UInt64) -> [(String, [GameResult])] {
        var out: [(String, [GameResult])] = []
        for sA in strategies {
            for sB in strategies {
                let cell = "\(sA.name) vs \(sB.name)"
                guard let deckA = deck(for: sA.civilization),
                      let deckB = deck(for: sB.civilization) else { continue }
                let cellSeed = baseSeed &+ hash(cell)
                let results = simulate(deckA: deckA, strategyA: sA,
                                       deckB: deckB, strategyB: sB,
                                       games: gamesPerCell, baseSeed: cellSeed)
                out.append((cell, results))
            }
        }
        return out
    }

    private func mirrorMatrix(gamesPerCell: Int, baseSeed: UInt64) -> [(String, [GameResult])] {
        var out: [(String, [GameResult])] = []
        for s in strategies {
            guard let deck = deck(for: s.civilization) else { continue }
            let cell = "\(s.name) mirror"
            let cellSeed = baseSeed &+ hash(cell)
            let results = simulate(deckA: deck, strategyA: s,
                                   deckB: deck, strategyB: s,
                                   games: gamesPerCell, baseSeed: cellSeed)
            out.append((cell, results))
        }
        return out
    }

    // MARK: - Helpers

    private func deck(for civ: Civilization) -> DeckList? {
        decks.values.first(where: { $0.civilization == civ })
    }

    /// Stable string hash → UInt64, used to mix per-cell seeds.
    private func hash(_ s: String) -> UInt64 {
        var h: UInt64 = 14695981039346656037
        for byte in s.utf8 {
            h ^= UInt64(byte)
            h = h &* 1099511628211
        }
        return h
    }
}
