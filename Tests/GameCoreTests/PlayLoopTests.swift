import XCTest
@testable import GameCore

/// Play-loop correctness tests (M1-1 single-copy removal, M1-4 one resource per turn).
/// Strict TDD: every test was RED before the corresponding implementation fix.
final class PlayLoopTests: XCTestCase {

    // MARK: - Helpers

    /// Build a minimal GameState for play-loop unit tests.
    /// Cards are constructed inline (no YAML loading). `cardsById` is populated
    /// so `state.card(for:)` succeeds for every id in empireHand / tacticsHand.
    private func makeState(
        empireHand: [String] = [],
        tacticsHand: [String] = [],
        resources: [ResourceInPlay] = [],
        cards: [String: Card] = [:]
    ) -> GameState {
        // Merge hand ids into the catalog if not already present.
        var allCards = cards
        for id in empireHand where allCards[id] == nil {
            allCards[id] = Card(id: id, name: id, civilization: .mongoles,
                                type: .resource, cost: .zero)
        }
        for id in tacticsHand where allCards[id] == nil {
            allCards[id] = Card(id: id, name: id, civilization: .mongoles,
                                type: .order, cost: .zero)
        }

        let player0 = PlayerState(
            index: 0, civilization: .mongoles,
            strongholdCardId: "sh_test",
            strongWeak: StrongWeakResources(strong: .food, weak: .wood),
            provinces: [ProvinceInPlay(cardId: "p0", baseDefense: 5, isStronghold: true)],
            resources: resources,
            empireHand: empireHand,
            tacticsHand: tacticsHand
        )
        let player1 = PlayerState(
            index: 1, civilization: .britanos,
            strongholdCardId: "sh_test1",
            strongWeak: StrongWeakResources(strong: .gold, weak: .wood),
            provinces: [ProvinceInPlay(cardId: "p1", baseDefense: 5, isStronghold: true)],
            resources: []
        )
        return GameState(
            players: [player0, player1],
            destinyMap: [],
            round: 1, current: 0,
            rng: RandomSource(seed: 42),
            rules: Rules(),
            cardsById: allCards
        )
    }

    /// Shorthand: build a RulesEngine with trivial pass-only strategies.
    private func makeEngine() -> RulesEngine {
        RulesEngine(
            strategyA: Strategy(name: "testA", civilization: .mongoles, priorities: Strategy.Priorities()),
            strategyB: Strategy(name: "testB", civilization: .mongoles, priorities: Strategy.Priorities()),
            firstPlayer: 0
        )
    }

    // MARK: Phase 1 — M1-1 single-copy removal

    // --- 1.2 RED: resource single-copy ---
    func testPlayResourceRemovesExactlyOneCopy() {
        var state = makeState(
            empireHand: ["res_a", "res_a"],
            resources: [ResourceInPlay(cardId: "start", production: ResourceAmount(food: 3, wood: 0, gold: 0), isReady: true)],
            cards: [
                "res_a": Card(id: "res_a", name: "res_a", civilization: .mongoles,
                              type: .resource, cost: ResourceAmount(food: 2, wood: 0, gold: 0),
                              production: ResourceAmount(food: 1, wood: 0, gold: 0))
            ]
        )
        var counters = LiveCounters()
        let engine = makeEngine()
        let result = engine.perform(action: .playResource(cardId: "res_a"), state: &state,
                                     playerIdx: 0, counters: &counters)
        XCTAssertTrue(result.performed, "first play should succeed")
        XCTAssertEqual(state.players[0].empireHand, ["res_a"],
                       "exactly one copy should remain")
    }

    // --- 1.4 RED: unit single-copy ---
    func testPlayUnitRemovesExactlyOneCopy() {
        var state = makeState(
            empireHand: ["unit_a", "unit_a"],
            resources: [ResourceInPlay(cardId: "start", production: ResourceAmount(food: 3, wood: 0, gold: 0), isReady: true)],
            cards: [
                "unit_a": Card(id: "unit_a", name: "unit_a", civilization: .mongoles,
                               type: .unit, cost: ResourceAmount(food: 2, wood: 0, gold: 0),
                               stats: Stats(attack: 2, defense: 2))
            ]
        )
        var counters = LiveCounters()
        let engine = makeEngine()
        let result = engine.perform(action: .playUnit(cardId: "unit_a"), state: &state,
                                     playerIdx: 0, counters: &counters)
        XCTAssertTrue(result.performed, "play should succeed")
        XCTAssertEqual(state.players[0].empireHand, ["unit_a"],
                       "exactly one copy should remain")
    }

    // --- 1.6 RED: building single-copy ---
    func testPlayBuildingRemovesExactlyOneCopy() {
        var state = makeState(
            empireHand: ["bldg_a", "bldg_a"],
            resources: [ResourceInPlay(cardId: "start", production: ResourceAmount(food: 3, wood: 0, gold: 0), isReady: true)],
            cards: [
                "bldg_a": Card(id: "bldg_a", name: "bldg_a", civilization: .mongoles,
                                type: .building, cost: ResourceAmount(food: 2, wood: 0, gold: 0))
            ]
        )
        var counters = LiveCounters()
        let engine = makeEngine()
        let result = engine.perform(action: .playBuilding(cardId: "bldg_a"), state: &state,
                                     playerIdx: 0, counters: &counters)
        XCTAssertTrue(result.performed, "play should succeed")
        XCTAssertEqual(state.players[0].empireHand, ["bldg_a"],
                       "exactly one copy should remain")
    }

    // --- 1.8 RED: tactic single-copy ---
    func testPlayTacticRemovesExactlyOneCopy() {
        var state = makeState(
            tacticsHand: ["tac_a", "tac_a"],
            cards: [
                "tac_a": Card(id: "tac_a", name: "tac_a", civilization: .mongoles,
                              type: .order, effects: [.revealTacticsTop(count: 1)])
            ]
        )
        var counters = LiveCounters()
        let engine = makeEngine()
        let result = engine.perform(action: .playTactic(cardId: "tac_a"), state: &state,
                                     playerIdx: 0, counters: &counters)
        XCTAssertTrue(result.performed, "play should succeed")
        XCTAssertEqual(state.players[0].tacticsHand, ["tac_a"],
                       "exactly one copy should remain")
    }

    // --- 1.10a RED: resource not-in-hand rejected ---
    func testPlayResourceNotInHandIsRejected() {
        var state = makeState(
            empireHand: [],
            cards: [
                "res_a": Card(id: "res_a", name: "res_a", civilization: .mongoles,
                              type: .resource, cost: .zero,
                              production: ResourceAmount(food: 1, wood: 0, gold: 0))
            ]
        )
        var counters = LiveCounters()
        let engine = makeEngine()
        let result = engine.perform(action: .playResource(cardId: "res_a"), state: &state,
                                     playerIdx: 0, counters: &counters)
        XCTAssertFalse(result.performed, "should not perform — card not in hand")
        XCTAssertTrue(result.continueTurn, "turn should continue")
    }

    // --- 1.10b RED: tactic not-in-hand rejected, no effects ---
    func testPlayTacticNotInHandIsRejectedNoEffects() {
        // Player has a tapped resource that would be untapped by the tactic.
        var state = makeState(
            tacticsHand: [],
            resources: [ResourceInPlay(cardId: "r1", production: ResourceAmount(food: 1, wood: 0, gold: 0), isReady: false)],
            cards: [
                "tac_a": Card(id: "tac_a", name: "tac_a", civilization: .mongoles,
                              type: .order,
                              effects: [.untapResources(count: 99, produces: nil)])
            ]
        )
        var counters = LiveCounters()
        let engine = makeEngine()
        let result = engine.perform(action: .playTactic(cardId: "tac_a"), state: &state,
                                     playerIdx: 0, counters: &counters)
        XCTAssertFalse(result.performed, "should not perform — card not in hand")
        XCTAssertTrue(result.continueTurn, "turn should continue")
        XCTAssertFalse(state.players[0].resources[0].isReady,
                      "resource should remain tapped — no effects fired")
    }

    // --- 1.11 RED: payment failure removes nothing ---
    func testPaymentFailureRemovesNothing() {
        var state = makeState(
            empireHand: ["res_a", "res_a"],
            resources: [],  // no resources → cannot pay
            cards: [
                "res_a": Card(id: "res_a", name: "res_a", civilization: .mongoles,
                              type: .resource, cost: ResourceAmount(food: 1, wood: 0, gold: 0),
                              production: ResourceAmount(food: 1, wood: 0, gold: 0))
            ]
        )
        var counters = LiveCounters()
        let engine = makeEngine()
        let result = engine.perform(action: .playResource(cardId: "res_a"), state: &state,
                                     playerIdx: 0, counters: &counters)
        XCTAssertFalse(result.performed, "payment should fail")
        XCTAssertEqual(state.players[0].empireHand, ["res_a", "res_a"],
                       "no cards should be removed")
    }

    // MARK: Phase 2 — M1-4 one resource per turn
    // (Tests enabled after Phase 1 commit and hasDeployedResourceThisTurn is added.)

    // --- 2.1 RED: second resource same turn rejected ---
    func testSecondResourceSameTurnIsRejected() {
        let startRes = ResourceInPlay(cardId: "start", production: ResourceAmount(food: 5, wood: 0, gold: 0), isReady: true)
        var state = makeState(
            empireHand: ["res_a", "res_b"],
            resources: [startRes],
            cards: [
                "res_a": Card(id: "res_a", name: "res_a", civilization: .mongoles,
                              type: .resource, cost: ResourceAmount(food: 2, wood: 0, gold: 0),
                              production: ResourceAmount(food: 1, wood: 0, gold: 0)),
                "res_b": Card(id: "res_b", name: "res_b", civilization: .mongoles,
                              type: .resource, cost: ResourceAmount(food: 2, wood: 0, gold: 0),
                              production: ResourceAmount(food: 1, wood: 0, gold: 0))
            ]
        )
        var counters = LiveCounters()
        let engine = makeEngine()

        // First resource should succeed.
        let firstResult = engine.perform(action: .playResource(cardId: "res_a"), state: &state,
                                         playerIdx: 0, counters: &counters)
        XCTAssertTrue(firstResult.performed, "first resource should deploy")

        // Second resource should be rejected.
        let secondResult = engine.perform(action: .playResource(cardId: "res_b"), state: &state,
                                          playerIdx: 0, counters: &counters)
        XCTAssertFalse(secondResult.performed, "second resource should be rejected")
        XCTAssertTrue(secondResult.continueTurn, "turn should continue")
        XCTAssertTrue(state.players[0].empireHand.contains("res_b"),
                      "res_b should still be in hand")
    }

    // --- 2.3 REGRESSION: first resource succeeds, flag set ---
    func testFirstResourceInTurnSucceeds() {
        let startRes = ResourceInPlay(cardId: "start", production: ResourceAmount(food: 3, wood: 0, gold: 0), isReady: true)
        var state = makeState(
            empireHand: ["res_a"],
            resources: [startRes],
            cards: [
                "res_a": Card(id: "res_a", name: "res_a", civilization: .mongoles,
                              type: .resource, cost: ResourceAmount(food: 2, wood: 0, gold: 0),
                              production: ResourceAmount(food: 1, wood: 0, gold: 0))
            ]
        )
        var counters = LiveCounters()
        let engine = makeEngine()
        let result = engine.perform(action: .playResource(cardId: "res_a"), state: &state,
                                     playerIdx: 0, counters: &counters)
        XCTAssertTrue(result.performed, "first resource should succeed")
        XCTAssertTrue(state.players[0].hasDeployedResourceThisTurn,
                      "flag should be set after deploying a resource")
    }

    // --- 2.4 REGRESSION: flag resets each turn ---
    func testFlagResetsEachTurn() {
        // Both players have empty hands so AI always passes.
        let startRes = ResourceInPlay(cardId: "start", production: ResourceAmount(food: 3, wood: 0, gold: 0), isReady: true)
        var state = makeState(
            empireHand: [],
            resources: [startRes],
            cards: [:]
        )
        var counters = LiveCounters()
        let engine = makeEngine()

        // Run turn for player 0 (AI passes since hand empty).
        engine.takeTurnForTest(state: &state, playerIdx: 0, counters: &counters)
        XCTAssertFalse(state.players[0].hasDeployedResourceThisTurn,
                       "flag should be false — nothing was deployed")

        // Now give player 0 a resource to play and deploy it.
        let resACard = Card(id: "res_a", name: "res_a", civilization: .mongoles,
                            type: .resource, cost: ResourceAmount(food: 2, wood: 0, gold: 0),
                            production: ResourceAmount(food: 1, wood: 0, gold: 0))
        var updatedCards = state.cardsById
        updatedCards["res_a"] = resACard
        state.players[0].empireHand = ["res_a"]
        state = GameState(
            players: state.players,
            destinyMap: state.destinyMap,
            round: state.round, current: state.current,
            rng: state.rng, rules: state.rules,
            cardsById: updatedCards
        )

        counters = LiveCounters()
        let deployResult = engine.perform(action: .playResource(cardId: "res_a"), state: &state,
                                           playerIdx: 0, counters: &counters)
        XCTAssertTrue(deployResult.performed, "resource should deploy")
        XCTAssertTrue(state.players[0].hasDeployedResourceThisTurn)

        // Run another turn for player 0; takeTurn resets the flag at the start.
        engine.takeTurnForTest(state: &state, playerIdx: 0, counters: &counters)
        XCTAssertFalse(state.players[0].hasDeployedResourceThisTurn,
                       "flag should reset at start of next turn")

        // Give another resource and verify it can be deployed on the new turn.
        let resBCard = Card(id: "res_b", name: "res_b", civilization: .mongoles,
                            type: .resource, cost: ResourceAmount(food: 2, wood: 0, gold: 0),
                            production: ResourceAmount(food: 1, wood: 0, gold: 0))
        var cardsTwo = state.cardsById
        cardsTwo["res_b"] = resBCard
        state.players[0].empireHand = ["res_b"]
        state = GameState(
            players: state.players,
            destinyMap: state.destinyMap,
            round: state.round, current: state.current,
            rng: state.rng, rules: state.rules,
            cardsById: cardsTwo
        )
        let deployAgain = engine.perform(action: .playResource(cardId: "res_b"), state: &state,
                                          playerIdx: 0, counters: &counters)
        XCTAssertTrue(deployAgain.performed, "resource should deploy on new turn")
    }

    // --- 2.5 REGRESSION: failed payment does not consume slot ---
    func testFailedPaymentDoesNotConsumeSlot() {
        // Starting resource: 1 gold. res_a costs 2 gold (unpayable).
        // res_b costs 0, produces 2 gold.
        // After res_b, player has 3 gold → res_a is payable, but slot is consumed.
        let startRes = ResourceInPlay(cardId: "start", production: ResourceAmount(food: 0, wood: 0, gold: 1), isReady: true)
        var state = makeState(
            empireHand: ["res_a", "res_b"],
            resources: [startRes],
            cards: [
                "res_a": Card(id: "res_a", name: "res_a", civilization: .mongoles,
                              type: .resource, cost: ResourceAmount(food: 0, wood: 0, gold: 2),
                              production: ResourceAmount(food: 0, wood: 0, gold: 1)),
                "res_b": Card(id: "res_b", name: "res_b", civilization: .mongoles,
                              type: .resource, cost: .zero,
                              production: ResourceAmount(food: 0, wood: 0, gold: 2))
            ]
        )
        var counters = LiveCounters()
        let engine = makeEngine()

        // Attempt res_a → fails (cannot pay 2 gold with 1).
        let attemptOne = engine.perform(action: .playResource(cardId: "res_a"), state: &state,
                                         playerIdx: 0, counters: &counters)
        XCTAssertFalse(attemptOne.performed, "res_a should fail — unpayable")
        XCTAssertFalse(state.players[0].hasDeployedResourceThisTurn,
                       "slot should NOT be consumed by failed payment")

        // Play res_b → succeeds (free).
        let freeDeploy = engine.perform(action: .playResource(cardId: "res_b"), state: &state,
                                         playerIdx: 0, counters: &counters)
        XCTAssertTrue(freeDeploy.performed, "res_b should succeed — free")
        XCTAssertTrue(state.players[0].hasDeployedResourceThisTurn,
                       "slot IS consumed now")

        // Attempt res_a again → economically payable (3 gold now), but slot used.
        let attemptTwo = engine.perform(action: .playResource(cardId: "res_a"), state: &state,
                                         playerIdx: 0, counters: &counters)
        XCTAssertFalse(attemptTwo.performed, "res_a should be rejected — slot consumed")
        XCTAssertTrue(state.players[0].empireHand.contains("res_a"),
                      "res_a should still be in hand")
    }
}
