import XCTest
@testable import GameCore

/// End-to-end setup tests: load real data, build players + destiny map, and
/// verify the GameState construction respects rules (victory params, province
/// layout, starting resources with strong/weak adjustment).
final class GameSetupTests: XCTestCase {

    private func loadWorld() throws -> (cards: [String: Card], rules: Rules,
                                        decks: [String: DeckList],
                                        destinyDef: DestinyMapDef) {
        let locator = try DataLocator()
        let loader = CardLoader(locator: locator)
        let cards = try loader.loadAllCards()
        let rules = try loader.loadRules()
        let decks = try loader.loadAllDecks()
        let destinyDef = try loader.loadDestinyMap()
        return (cards, rules, decks, destinyDef)
    }

    func testLoadingAllDataSucceeds() throws {
        let world = try loadWorld()
        XCTAssertGreaterThan(world.cards.count, 150, "expected 171 cards")
        XCTAssertEqual(world.decks.count, 3)
        XCTAssertEqual(world.rules.version, "0.6")
    }

    func testBuildingPlayerFromMongolDeckAppliesStrongWeak() throws {
        let world = try loadWorld()
        let deck = try XCTUnwrap(world.decks["mongoles_v06"])
        let player = try GameSetup.makePlayer(index: 0, deck: deck,
                                              cards: world.cards, rules: world.rules)
        // Stronghold is Mongol: strong=gold, weak=wood.
        XCTAssertEqual(player.strongWeak.strong, .gold)
        XCTAssertEqual(player.strongWeak.weak, .wood)

        // 4 outer provinces + 1 stronghold province.
        XCTAssertEqual(player.provinces.count, 5)
        XCTAssertEqual(player.provinces.filter { $0.isStronghold }.count, 1)
        XCTAssertEqual(player.provinces.filter { !$0.isStronghold }.count, 4)
        XCTAssertTrue(player.provinces.first { $0.isStronghold }?.baseDefense == 7)

        // Starting resources: Ruta de la Seda prints 0/0/2 gold; with strong=gold → 0/0/3.
        let silkIdx = player.resources.firstIndex { $0.cardId == "mongol_ruta_de_la_seda" }
        XCTAssertNotNil(silkIdx)
        XCTAssertEqual(player.resources[silkIdx!].production.gold, 3, "strong gold → +1")

        // Mercado de Caravanas prints 0/1/1; weak=wood → wood floored to 0, strong=gold → 2.
        let marketIdx = player.resources.firstIndex { $0.cardId == "mongol_mercado_de_caravanas" }
        XCTAssertNotNil(marketIdx)
        XCTAssertEqual(player.resources[marketIdx!].production.wood, 0, "weak wood → 0")
        XCTAssertEqual(player.resources[marketIdx!].production.gold, 2, "strong gold → +1 (1→2)")
    }

    func testStrongholdExposedAfterAllOuterBroken() throws {
        let world = try loadWorld()
        let deck = try XCTUnwrap(world.decks["mongoles_v06"])
        var player = try GameSetup.makePlayer(index: 0, deck: deck,
                                              cards: world.cards, rules: world.rules)
        XCTAssertFalse(player.strongholdExposed)
        for i in player.provinces.indices where !player.provinces[i].isStronghold {
            player.provinces[i].isBroken = true
        }
        XCTAssertTrue(player.strongholdExposed, "stronghold exposed once all outer broken")
    }

    func testDestinyMapHasFiveCategories() throws {
        let world = try loadWorld()
        var rng = RandomSource(seed: 42)
        let map = try GameSetup.makeDestinyMap(def: world.destinyDef,
                                               cards: world.cards, rng: &rng)
        XCTAssertEqual(map.count, 5)
        let categories = Set(map.map { $0.category })
        XCTAssertEqual(categories.count, 5, "one of each category")
    }

    func testDestinyMapIsDeterministicBySeed() throws {
        let world = try loadWorld()
        var rng1 = RandomSource(seed: 42)
        var rng2 = RandomSource(seed: 42)
        let map1 = try GameSetup.makeDestinyMap(def: world.destinyDef,
                                                cards: world.cards, rng: &rng1)
        let map2 = try GameSetup.makeDestinyMap(def: world.destinyDef,
                                                cards: world.cards, rng: &rng2)
        XCTAssertEqual(map1.map { $0.cardId }, map2.map { $0.cardId },
                       "same seed → same destiny map")
    }
}
