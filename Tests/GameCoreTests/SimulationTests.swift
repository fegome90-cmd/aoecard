import XCTest
@testable import GameCore

/// Simulation tests — determinism with seed, initiative alternation, and that
/// real matchups run to completion and produce a winner or stall.
final class SimulationTests: XCTestCase {

    private func makeSimulator() throws -> Simulator {
        let locator = try DataLocator()
        let loader = CardLoader(locator: locator)
        let cards = try loader.loadAllCards()
        let rules = try loader.loadRules()
        let decks = try loader.loadAllDecks()
        let destinyDef = try loader.loadDestinyMap()
        let catalog = try loader.loadStrategies()
        return Simulator(cards: cards, rules: rules, decks: decks,
                         strategies: catalog.strategies, destinyDef: destinyDef)
    }

    // MARK: - Test 10: determinism with seed

    func testSameSeedProducesIdenticalResult() throws {
        let sim = try makeSimulator()
        let deckA = try XCTUnwrap(sim.decks.values.first { $0.civilization == .mongoles })
        let deckB = try XCTUnwrap(sim.decks.values.first { $0.civilization == .britanos })
        let sA = try XCTUnwrap(sim.strategies.first { $0.civilization == .mongoles })
        let sB = try XCTUnwrap(sim.strategies.first { $0.civilization == .britanos })

        let r1 = sim.playOne(deckA: deckA, strategyA: sA,
                             deckB: deckB, strategyB: sB, seed: 42)
        let r2 = sim.playOne(deckA: deckA, strategyA: sA,
                             deckB: deckB, strategyB: sB, seed: 42)

        XCTAssertEqual(r1.winner, r2.winner, "same seed → same winner")
        XCTAssertEqual(r1.rounds, r2.rounds, "same seed → same rounds")
        XCTAssertEqual(r1.winCondition, r2.winCondition)
        XCTAssertEqual(r1.cardsPlayed, r2.cardsPlayed)
        XCTAssertEqual(r1.unitsDestroyed, r2.unitsDestroyed)
        XCTAssertEqual(r1.assaultsDeclared, r2.assaultsDeclared)
        XCTAssertEqual(r1.incursionsDeclared, r2.incursionsDeclared)
    }

    func testDifferentSeedMayProduceDifferentResult() throws {
        let sim = try makeSimulator()
        let deckA = try XCTUnwrap(sim.decks.values.first { $0.civilization == .mongoles })
        let deckB = try XCTUnwrap(sim.decks.values.first { $0.civilization == .britanos })
        let sA = try XCTUnwrap(sim.strategies.first { $0.civilization == .mongoles })
        let sB = try XCTUnwrap(sim.strategies.first { $0.civilization == .britanos })

        // Run several seeds; not all should be identical (would indicate the
        // RNG is unused). We just require that at least two differ in some
        // recorded field.
        var seen = Set<Int>()
        for seed in UInt64(1)...20 {
            let result = sim.playOne(deckA: deckA, strategyA: sA,
                                deckB: deckB, strategyB: sB, seed: seed)
            seen.insert(result.rounds &* 1000 &+ (result.winner ?? -1))
        }
        XCTAssertGreaterThan(seen.count, 1, "different seeds should produce varied outcomes")
    }

    // MARK: - Test 8: initiative alternation

    func testInitiativeAlternatesBetweenRounds() throws {
        // Initiative is modeled by `alternateInitiative()` on GameState. We
        // verify it flips current player each round.
        let locator = try DataLocator()
        let loader = CardLoader(locator: locator)
        let rules = try loader.loadRules()
        var state = GameState(players: [
            PlayerState(index: 0, civilization: .mongoles, strongholdCardId: "s",
                        strongWeak: StrongWeakResources(strong: .gold, weak: .wood),
                        provinces: [], resources: []),
            PlayerState(index: 1, civilization: .britanos, strongholdCardId: "s",
                        strongWeak: StrongWeakResources(strong: .wood, weak: .food),
                        provinces: [], resources: [])
        ], destinyMap: [], round: 1, current: 0,
           rng: RandomSource(seed: 1), rules: rules, cardsById: [:])
        XCTAssertEqual(state.current, 0)
        state.alternateInitiative()
        XCTAssertEqual(state.current, 1, "initiative flips to 1")
        state.alternateInitiative()
        XCTAssertEqual(state.current, 0, "initiative flips back to 0")
    }

    // MARK: - Full matches run cleanly

    func testMatchRunsToCompletion() throws {
        let sim = try makeSimulator()
        let deckA = try XCTUnwrap(sim.decks.values.first { $0.civilization == .mongoles })
        let deckB = try XCTUnwrap(sim.decks.values.first { $0.civilization == .mapuches })
        let sA = try XCTUnwrap(sim.strategies.first { $0.name == "Ruta-Incursión" })
        let sB = try XCTUnwrap(sim.strategies.first { $0.name == "Malón Contraataque" })

        let result = sim.playOne(deckA: deckA, strategyA: sA,
                            deckB: deckB, strategyB: sB, seed: 7)
        XCTAssertGreaterThanOrEqual(result.rounds, 1, "match should run at least one round")
        XCTAssertLessThanOrEqual(result.rounds, sim.rules.victory.maxRounds,
                                 "match should respect maxRounds")
        // Winner is 0, 1, or nil (stall); all valid.
        XCTAssertTrue(result.winner == nil || result.winner == 0 || result.winner == 1)
    }

    func testSimulateBatchProducesRequestedCount() throws {
        let sim = try makeSimulator()
        let deckA = try XCTUnwrap(sim.decks.values.first { $0.civilization == .mongoles })
        let deckB = try XCTUnwrap(sim.decks.values.first { $0.civilization == .britanos })
        let sA = try XCTUnwrap(sim.strategies.first { $0.civilization == .mongoles })
        let sB = try XCTUnwrap(sim.strategies.first { $0.civilization == .britanos })
        let results = sim.simulate(deckA: deckA, strategyA: sA,
                                   deckB: deckB, strategyB: sB,
                                   games: 100, baseSeed: 123)
        XCTAssertEqual(results.count, 100)
    }

    func testCivMatrixRunsAllPairings() throws {
        let sim = try makeSimulator()
        let matrix = sim.runMatrix(mode: .civ, gamesPerCell: 5, baseSeed: 1)
        XCTAssertEqual(matrix.count, 9, "3×3 civ matchups")
        for (_, results) in matrix {
            XCTAssertEqual(results.count, 5)
        }
    }

    func testStrategyMatrixRunsAllPairings() throws {
        let sim = try makeSimulator()
        let matrix = sim.runMatrix(mode: .strategy, gamesPerCell: 2, baseSeed: 1)
        XCTAssertEqual(matrix.count, 225, "15×15 strategy pairings")
    }

    func testMirrorMatrixRunsAllStrategies() throws {
        let sim = try makeSimulator()
        let matrix = sim.runMatrix(mode: .mirror, gamesPerCell: 3, baseSeed: 1)
        XCTAssertEqual(matrix.count, 15, "one mirror per strategy")
    }

    // MARK: - Stats aggregation

    func testStatsAggregatorComputesWinRates() throws {
        let sim = try makeSimulator()
        let deckA = try XCTUnwrap(sim.decks.values.first { $0.civilization == .mongoles })
        let deckB = try XCTUnwrap(sim.decks.values.first { $0.civilization == .britanos })
        let sA = try XCTUnwrap(sim.strategies.first { $0.civilization == .mongoles })
        let sB = try XCTUnwrap(sim.strategies.first { $0.civilization == .britanos })
        let results = sim.simulate(deckA: deckA, strategyA: sA,
                                   deckB: deckB, strategyB: sB,
                                   games: 50, baseSeed: 999)
        let stats = StatsAggregator.matchupStats(label: "Mongoles vs Britanos", games: results)
        XCTAssertEqual(stats.games, 50)
        XCTAssertEqual(stats.winsA + stats.winsB + stats.stalls, 50)
        XCTAssertGreaterThanOrEqual(stats.winRateA, 0.0)
        XCTAssertLessThanOrEqual(stats.winRateA, 1.0)
    }
}
