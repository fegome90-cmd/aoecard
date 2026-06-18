import XCTest
@testable import GameCore

/// Shared builders for play-loop tests. Extracted so each test class stays
/// well under the type-body-length limit while sharing one setup contract.
///
/// Cards are constructed inline (no YAML loading). `cardsById` is populated so
/// `state.card(for:)` succeeds for every id in empireHand / tacticsHand.
fileprivate enum PlayLoopTestSupport {
    /// Build a minimal GameState for play-loop unit tests.
    static func makeState(
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
    static func makeEngine() -> RulesEngine {
        RulesEngine(
            strategyA: Strategy(name: "testA", civilization: .mongoles, priorities: Strategy.Priorities()),
            strategyB: Strategy(name: "testB", civilization: .mongoles, priorities: Strategy.Priorities()),
            firstPlayer: 0
        )
    }
}

/// Play-loop correctness — M1-1 single-copy removal (Phase 1) and the
/// verify-coverage gap closures (S4/S5/S6). Strict TDD: every test was RED
/// before the corresponding implementation fix.
final class PlayLoopTests: XCTestCase {

    // MARK: Phase 1 — M1-1 single-copy removal

    // --- 1.2 RED: resource single-copy ---
    func testPlayResourceRemovesExactlyOneCopy() {
        var state = PlayLoopTestSupport.makeState(
            empireHand: ["res_a", "res_a"],
            resources: [ResourceInPlay(cardId: "start", production: ResourceAmount(food: 3, wood: 0, gold: 0), isReady: true)],
            cards: [
                "res_a": Card(id: "res_a", name: "res_a", civilization: .mongoles,
                              type: .resource, cost: ResourceAmount(food: 2, wood: 0, gold: 0),
                              production: ResourceAmount(food: 1, wood: 0, gold: 0))
            ]
        )
        var counters = LiveCounters()
        let engine = PlayLoopTestSupport.makeEngine()
        let result = engine.perform(action: .playResource(cardId: "res_a"), state: &state,
                                     playerIdx: 0, counters: &counters)
        XCTAssertTrue(result.performed, "first play should succeed")
        XCTAssertEqual(state.players[0].empireHand, ["res_a"],
                       "exactly one copy should remain")
    }

    // --- 1.4 RED: unit single-copy ---
    func testPlayUnitRemovesExactlyOneCopy() {
        var state = PlayLoopTestSupport.makeState(
            empireHand: ["unit_a", "unit_a"],
            resources: [ResourceInPlay(cardId: "start", production: ResourceAmount(food: 3, wood: 0, gold: 0), isReady: true)],
            cards: [
                "unit_a": Card(id: "unit_a", name: "unit_a", civilization: .mongoles,
                               type: .unit, cost: ResourceAmount(food: 2, wood: 0, gold: 0),
                               stats: Stats(attack: 2, defense: 2))
            ]
        )
        var counters = LiveCounters()
        let engine = PlayLoopTestSupport.makeEngine()
        let result = engine.perform(action: .playUnit(cardId: "unit_a"), state: &state,
                                     playerIdx: 0, counters: &counters)
        XCTAssertTrue(result.performed, "play should succeed")
        XCTAssertEqual(state.players[0].empireHand, ["unit_a"],
                       "exactly one copy should remain")
    }

    // --- 1.6 RED: building single-copy ---
    func testPlayBuildingRemovesExactlyOneCopy() {
        var state = PlayLoopTestSupport.makeState(
            empireHand: ["bldg_a", "bldg_a"],
            resources: [ResourceInPlay(cardId: "start", production: ResourceAmount(food: 3, wood: 0, gold: 0), isReady: true)],
            cards: [
                "bldg_a": Card(id: "bldg_a", name: "bldg_a", civilization: .mongoles,
                                type: .building, cost: ResourceAmount(food: 2, wood: 0, gold: 0))
            ]
        )
        var counters = LiveCounters()
        let engine = PlayLoopTestSupport.makeEngine()
        let result = engine.perform(action: .playBuilding(cardId: "bldg_a"), state: &state,
                                     playerIdx: 0, counters: &counters)
        XCTAssertTrue(result.performed, "play should succeed")
        XCTAssertEqual(state.players[0].empireHand, ["bldg_a"],
                       "exactly one copy should remain")
    }

    // --- 1.8 RED: tactic single-copy ---
    func testPlayTacticRemovesExactlyOneCopy() {
        var state = PlayLoopTestSupport.makeState(
            tacticsHand: ["tac_a", "tac_a"],
            cards: [
                "tac_a": Card(id: "tac_a", name: "tac_a", civilization: .mongoles,
                              type: .order, effects: [.revealTacticsTop(count: 1)])
            ]
        )
        var counters = LiveCounters()
        let engine = PlayLoopTestSupport.makeEngine()
        let result = engine.perform(action: .playTactic(cardId: "tac_a"), state: &state,
                                     playerIdx: 0, counters: &counters)
        XCTAssertTrue(result.performed, "play should succeed")
        XCTAssertEqual(state.players[0].tacticsHand, ["tac_a"],
                       "exactly one copy should remain")
    }

    // --- 1.10a RED: resource not-in-hand rejected ---
    func testPlayResourceNotInHandIsRejected() {
        var state = PlayLoopTestSupport.makeState(
            empireHand: [],
            cards: [
                "res_a": Card(id: "res_a", name: "res_a", civilization: .mongoles,
                              type: .resource, cost: .zero,
                              production: ResourceAmount(food: 1, wood: 0, gold: 0))
            ]
        )
        var counters = LiveCounters()
        let engine = PlayLoopTestSupport.makeEngine()
        let result = engine.perform(action: .playResource(cardId: "res_a"), state: &state,
                                     playerIdx: 0, counters: &counters)
        XCTAssertFalse(result.performed, "should not perform — card not in hand")
        XCTAssertTrue(result.continueTurn, "turn should continue")
    }

    // --- 1.10b RED: tactic not-in-hand rejected, no effects ---
    func testPlayTacticNotInHandIsRejectedNoEffects() {
        // Player has a tapped resource that would be untapped by the tactic.
        var state = PlayLoopTestSupport.makeState(
            tacticsHand: [],
            resources: [ResourceInPlay(cardId: "r1", production: ResourceAmount(food: 1, wood: 0, gold: 0), isReady: false)],
            cards: [
                "tac_a": Card(id: "tac_a", name: "tac_a", civilization: .mongoles,
                              type: .order,
                              effects: [.untapResources(count: 99, produces: nil)])
            ]
        )
        var counters = LiveCounters()
        let engine = PlayLoopTestSupport.makeEngine()
        let result = engine.perform(action: .playTactic(cardId: "tac_a"), state: &state,
                                     playerIdx: 0, counters: &counters)
        XCTAssertFalse(result.performed, "should not perform — card not in hand")
        XCTAssertTrue(result.continueTurn, "turn should continue")
        XCTAssertFalse(state.players[0].resources[0].isReady,
                      "resource should remain tapped — no effects fired")
    }

    // --- 1.11 RED: payment failure removes nothing ---
    func testPaymentFailureRemovesNothing() {
        var state = PlayLoopTestSupport.makeState(
            empireHand: ["res_a", "res_a"],
            resources: [],  // no resources → cannot pay
            cards: [
                "res_a": Card(id: "res_a", name: "res_a", civilization: .mongoles,
                              type: .resource, cost: ResourceAmount(food: 1, wood: 0, gold: 0),
                              production: ResourceAmount(food: 1, wood: 0, gold: 0))
            ]
        )
        var counters = LiveCounters()
        let engine = PlayLoopTestSupport.makeEngine()
        let result = engine.perform(action: .playResource(cardId: "res_a"), state: &state,
                                     playerIdx: 0, counters: &counters)
        XCTAssertFalse(result.performed, "payment should fail")
        XCTAssertEqual(state.players[0].empireHand, ["res_a", "res_a"],
                       "no cards should be removed")
    }

    // MARK: - Coverage gap closures (verify-report S4/S5/S6 PARTIAL → COMPLIANT)

    // --- S4: single-copy hand emptied to zero (was only proven for 2→1) ---
    func testSingleCopyHandEmptiesToZero() {
        var state = PlayLoopTestSupport.makeState(
            empireHand: ["res_a"],
            resources: [ResourceInPlay(cardId: "start", production: ResourceAmount(food: 3, wood: 0, gold: 0), isReady: true)],
            cards: [
                "res_a": Card(id: "res_a", name: "res_a", civilization: .mongoles,
                              type: .resource, cost: ResourceAmount(food: 2, wood: 0, gold: 0),
                              production: ResourceAmount(food: 1, wood: 0, gold: 0))
            ]
        )
        var counters = LiveCounters()
        let engine = PlayLoopTestSupport.makeEngine()
        let result = engine.perform(action: .playResource(cardId: "res_a"), state: &state,
                                     playerIdx: 0, counters: &counters)
        XCTAssertTrue(result.performed, "play should succeed")
        XCTAssertTrue(state.players[0].empireHand.isEmpty,
                      "single-copy hand should be emptied (S4: single-copy unaffected in count)")
    }

    // --- S5: remaining copy after a play is still playable (Judgment Day F11) ---
    func testRemainingCopyAfterPlayIsStillPlayable() {
        var state = PlayLoopTestSupport.makeState(
            empireHand: ["res_a", "res_a"],
            resources: [ResourceInPlay(cardId: "start", production: ResourceAmount(food: 5, wood: 0, gold: 0), isReady: true)],
            cards: [
                "res_a": Card(id: "res_a", name: "res_a", civilization: .mongoles,
                              type: .resource, cost: ResourceAmount(food: 2, wood: 0, gold: 0),
                              production: ResourceAmount(food: 2, wood: 0, gold: 0))
            ]
        )
        var counters = LiveCounters()
        let engine = PlayLoopTestSupport.makeEngine()

        // First play on turn N: removes one copy.
        let first = engine.perform(action: .playResource(cardId: "res_a"), state: &state,
                                    playerIdx: 0, counters: &counters)
        XCTAssertTrue(first.performed, "first play should succeed")
        XCTAssertEqual(state.players[0].empireHand, ["res_a"],
                       "one copy should remain after first play")

        // The flag is now set for this turn; reset it to simulate a new turn
        // so the remaining copy can be played (M1-4 only blocks same-turn repeats).
        state.players[0].hasDeployedResourceThisTurn = false

        // Second play on the SAME card id: must succeed and empty the hand.
        // This pins that firstIndex+remove(at:) doesn't corrupt the array on
        // the second invocation, and the guard doesn't reject a legitimate
        // second copy (Judgment Day F11).
        let second = engine.perform(action: .playResource(cardId: "res_a"), state: &state,
                                     playerIdx: 0, counters: &counters)
        XCTAssertTrue(second.performed, "second play on remaining copy should succeed")
        XCTAssertTrue(state.players[0].empireHand.isEmpty,
                      "remaining copy should be removed — hand empty")
    }

    // --- S6: empty hand rejects ALL play action types, no crash ---
    func testEmptyHandRejectsAllPlayActions() {
        var state = PlayLoopTestSupport.makeState(
            empireHand: [],
            tacticsHand: [],
            resources: [ResourceInPlay(cardId: "start", production: ResourceAmount(food: 3, wood: 0, gold: 0), isReady: true)],
            cards: [
                "res_a": Card(id: "res_a", name: "res_a", civilization: .mongoles,
                              type: .resource, cost: ResourceAmount(food: 2, wood: 0, gold: 0)),
                "unit_a": Card(id: "unit_a", name: "unit_a", civilization: .mongoles,
                               type: .unit, cost: ResourceAmount(food: 2, wood: 0, gold: 0),
                               stats: Stats(attack: 2, defense: 2)),
                "bldg_a": Card(id: "bldg_a", name: "bldg_a", civilization: .mongoles,
                               type: .building, cost: ResourceAmount(food: 2, wood: 0, gold: 0)),
                "tac_a": Card(id: "tac_a", name: "tac_a", civilization: .mongoles,
                              type: .order, effects: [.revealTacticsTop(count: 1)])
            ]
        )
        var counters = LiveCounters()
        let engine = PlayLoopTestSupport.makeEngine()

        // Empty empire hand: resource / unit / building all rejected.
        let resourceResult = engine.perform(action: .playResource(cardId: "res_a"), state: &state,
                                playerIdx: 0, counters: &counters)
        let unitResult = engine.perform(action: .playUnit(cardId: "unit_a"), state: &state,
                                playerIdx: 0, counters: &counters)
        let buildingResult = engine.perform(action: .playBuilding(cardId: "bldg_a"), state: &state,
                                playerIdx: 0, counters: &counters)
        // Empty tactics hand: tactic rejected.
        let tacticResult = engine.perform(action: .playTactic(cardId: "tac_a"), state: &state,
                                playerIdx: 0, counters: &counters)

        XCTAssertFalse(resourceResult.performed, "playResource on empty hand must be rejected")
        XCTAssertFalse(unitResult.performed, "playUnit on empty hand must be rejected")
        XCTAssertFalse(buildingResult.performed, "playBuilding on empty hand must be rejected")
        XCTAssertFalse(tacticResult.performed, "playTactic on empty tactics hand must be rejected")
        XCTAssertTrue(resourceResult.continueTurn && unitResult.continueTurn && buildingResult.continueTurn && tacticResult.continueTurn,
                      "turn must continue after each rejection")
        // No crash reaching this point is itself the S6 invariant.
    }
}

/// Play-loop correctness — M1-4 one resource per turn (Phase 2) plus the
/// simulator-fidelity integration test (StrategyAI × one-resource-per-turn).
/// Strict TDD: every test was RED before the corresponding implementation fix.
final class PlayLoopResourceSlotTests: XCTestCase {

    // MARK: Phase 2 — M1-4 one resource per turn

    // --- 2.1 RED: second resource same turn rejected ---
    func testSecondResourceSameTurnIsRejected() {
        let startRes = ResourceInPlay(cardId: "start", production: ResourceAmount(food: 5, wood: 0, gold: 0), isReady: true)
        var state = PlayLoopTestSupport.makeState(
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
        let engine = PlayLoopTestSupport.makeEngine()

        // First resource should succeed.
        let firstResult = engine.perform(action: .playResource(cardId: "res_a"), state: &state,
                                         playerIdx: 0, counters: &counters)
        XCTAssertTrue(firstResult.performed, "first resource should deploy")

        // Capture economy state BEFORE the rejected second deploy, so we can prove
        // a rejected resource performs zero side effects (no taps, no waste).
        let readinessBefore = state.players[0].resources.map(\.isReady)
        let wasteBefore = state.wasteByPlayer[0]

        // Second resource should be rejected.
        let secondResult = engine.perform(action: .playResource(cardId: "res_b"), state: &state,
                                          playerIdx: 0, counters: &counters)
        XCTAssertFalse(secondResult.performed, "second resource should be rejected")
        XCTAssertTrue(secondResult.continueTurn, "turn should continue")
        XCTAssertTrue(state.players[0].empireHand.contains("res_b"),
                      "res_b should still be in hand")
        XCTAssertEqual(state.players[0].resources.map(\.isReady), readinessBefore,
                       "rejected second resource must not tap any resources")
        XCTAssertEqual(state.wasteByPlayer[0], wasteBefore,
                       "rejected second resource must not change waste")
    }

    // --- 2.3 REGRESSION: first resource succeeds, flag set ---
    func testFirstResourceInTurnSucceeds() {
        let startRes = ResourceInPlay(cardId: "start", production: ResourceAmount(food: 3, wood: 0, gold: 0), isReady: true)
        var state = PlayLoopTestSupport.makeState(
            empireHand: ["res_a"],
            resources: [startRes],
            cards: [
                "res_a": Card(id: "res_a", name: "res_a", civilization: .mongoles,
                              type: .resource, cost: ResourceAmount(food: 2, wood: 0, gold: 0),
                              production: ResourceAmount(food: 1, wood: 0, gold: 0))
            ]
        )
        var counters = LiveCounters()
        let engine = PlayLoopTestSupport.makeEngine()
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
        var state = PlayLoopTestSupport.makeState(
            empireHand: [],
            resources: [startRes],
            cards: [:]
        )
        var counters = LiveCounters()
        let engine = PlayLoopTestSupport.makeEngine()

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
        var state = PlayLoopTestSupport.makeState(
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
        let engine = PlayLoopTestSupport.makeEngine()

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

        // Capture economy state BEFORE the rejected third attempt (res_a retry that
        // is now economically payable but slot-blocked), to prove it has zero side
        // effects: no taps, no waste, no hand mutation.
        let readinessBefore = state.players[0].resources.map(\.isReady)
        let wasteBefore = state.wasteByPlayer[0]

        // Attempt res_a again → economically payable (3 gold now), but slot used.
        let attemptTwo = engine.perform(action: .playResource(cardId: "res_a"), state: &state,
                                         playerIdx: 0, counters: &counters)
        XCTAssertFalse(attemptTwo.performed, "res_a should be rejected — slot consumed")
        XCTAssertTrue(state.players[0].empireHand.contains("res_a"),
                      "res_a should still be in hand")
        XCTAssertEqual(state.players[0].resources.map(\.isReady), readinessBefore,
                       "rejected slot-consumed resource must not tap any resources")
        XCTAssertEqual(state.wasteByPlayer[0], wasteBefore,
                       "rejected slot-consumed resource must not change waste")
    }

    // MARK: - Simulator fidelity (M1-4 × StrategyAI integration)

    // --- S11 / one-resource-per-turn: AI continues with other actions after the
    // first resource, instead of exhausting the failure budget on rejected resources.
    //
    // RED today: StrategyAI.legalActions() still offers payable resources AFTER the
    // one-resource-per-turn slot is used, so perform() keeps rejecting them. The
    // `consecutiveFailures < 4` budget is drained on resources before the unit is
    // ever reached, ending the turn early. This distorts every simulation, even
    // though perform() itself is correct. GREEN requires legalActions() to honor
    // hasDeployedResourceThisTurn so the slot-occupying flag is a single source of
    // truth shared by the producer and the consumer.
    func testAIContinuesWithUnitAfterFirstResource() {
        // Hand: two payable resources + one payable unit. Priority resource > unit,
        // so the AI prefers resources first (the worst case for the bug).
        let startRes = ResourceInPlay(cardId: "start",
                                      production: ResourceAmount(food: 5, wood: 0, gold: 0),
                                      isReady: true)
        var state = PlayLoopTestSupport.makeState(
            empireHand: ["res_a", "res_b", "unit_a"],
            resources: [startRes],
            cards: [
                "res_a": Card(id: "res_a", name: "res_a", civilization: .mongoles,
                              type: .resource, cost: .zero,
                              production: ResourceAmount(food: 1, wood: 0, gold: 0)),
                "res_b": Card(id: "res_b", name: "res_b", civilization: .mongoles,
                              type: .resource, cost: .zero,
                              production: ResourceAmount(food: 1, wood: 0, gold: 0)),
                "unit_a": Card(id: "unit_a", name: "unit_a", civilization: .mongoles,
                               type: .unit, cost: ResourceAmount(food: 2, wood: 0, gold: 0),
                               stats: Stats(attack: 2, defense: 2))
            ]
        )
        // Strategy: resource clearly preferred over unit so the AI exhausts the
        // failure budget on the second resource before ever reaching the unit.
        let engine = RulesEngine(
            strategyA: Strategy(name: "testA", civilization: .mongoles,
                                priorities: Strategy.Priorities(playResource: 1.0,
                                                                playUnit: 0.0)),
            strategyB: Strategy(name: "testB", civilization: .mongoles,
                                priorities: Strategy.Priorities()),
            firstPlayer: 0
        )

        var counters = LiveCounters()
        engine.takeTurnForTest(state: &state, playerIdx: 0, counters: &counters)

        // Exactly ONE resource deployed this turn (res_a XOR res_b), never two.
        let deployedResources = state.players[0].resources.filter {
            $0.cardId == "res_a" || $0.cardId == "res_b"
        }
        XCTAssertEqual(deployedResources.count, 1,
                       "exactly one resource must be deployed per turn")

        // The unit MUST have been deployed — proves the turn did NOT end early on
        // four consecutive rejected-resource failures. This is the distortion fix.
        XCTAssertTrue(state.players[0].units.contains { $0.cardId == "unit_a" },
                      "AI must continue to the unit after the first resource (turn not ended early)")

        XCTAssertTrue(state.players[0].hasDeployedResourceThisTurn,
                      "flag must be set after deploying a resource")
    }
}
