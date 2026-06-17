import XCTest
@testable import GameCore

/// Economy tests — production adjustment (strong/weak), and the PaymentSolver
/// subset search ([FIX 2]): exact payment, payment with minimal waste, the
/// anti-greedy case, and the impossible case.
final class EconomyTests: XCTestCase {

    // MARK: - Strong / weak resource adjustment (tests 3 from spec)

    func testStrongResourceGetsPlusOne() {
        let printed = ResourceAmount(food: 0, wood: 0, gold: 2)
        let sw = StrongWeakResources(strong: .gold, weak: .wood)
        let adjusted = Economy.adjustedProduction(printed, strongWeak: sw)
        XCTAssertEqual(adjusted.gold, 3, "gold is strong → +1")
        XCTAssertEqual(adjusted.wood, 0)
        XCTAssertEqual(adjusted.food, 0)
    }

    func testWeakResourceGetsMinusOneFlooredAtZero() {
        let printed = ResourceAmount(food: 0, wood: 1, gold: 0)
        let sw = StrongWeakResources(strong: .gold, weak: .wood)
        let adjusted = Economy.adjustedProduction(printed, strongWeak: sw)
        XCTAssertEqual(adjusted.wood, 0, "wood is weak → -1, floored at 0")
    }

    func testWeakResourceStaysNonNegativeWhenAlreadyZero() {
        let printed = ResourceAmount(food: 0, wood: 0, gold: 2)
        let sw = StrongWeakResources(strong: .gold, weak: .wood)
        let adjusted = Economy.adjustedProduction(printed, strongWeak: sw)
        XCTAssertEqual(adjusted.wood, 0, "floor at 0 even if 0-1")
    }

    func testNeutralResourceIsUnchanged() {
        let printed = ResourceAmount(food: 2, wood: 0, gold: 0)
        let sw = StrongWeakResources(strong: .gold, weak: .wood)
        let adjusted = Economy.adjustedProduction(printed, strongWeak: sw)
        XCTAssertEqual(adjusted.food, 2, "food is neither strong nor weak")
    }

    // MARK: - PaymentSolver ([FIX 2])

    private func res(_ production: ResourceAmount) -> ResourceInPlay {
        ResourceInPlay(cardId: "x", production: production)
    }

    func testExactPaymentNoWaste() {
        let ready = [
            res(ResourceAmount(food: 0, wood: 0, gold: 2)),
            res(ResourceAmount(food: 0, wood: 0, gold: 3))
        ]
        let cost = ResourceAmount(food: 0, wood: 0, gold: 2)
        let payment = Economy.solve(cost: cost, ready: ready)
        XCTAssertNotNil(payment)
        XCTAssertEqual(payment?.tappedResourceIds.count, 1, "should tap the 2-gold resource exactly")
        XCTAssertEqual(payment?.waste.total, 0, "no waste")
    }

    func testPaymentWithMinimalWasteRecorded() {
        // Cost 3 gold. Ready: a 2-gold and a 3-gold. The 3-gold alone covers with 0 waste.
        let ready = [
            res(ResourceAmount(food: 0, wood: 0, gold: 2)),
            res(ResourceAmount(food: 0, wood: 0, gold: 3))
        ]
        let cost = ResourceAmount(food: 0, wood: 0, gold: 3)
        let payment = Economy.solve(cost: cost, ready: ready)
        XCTAssertEqual(payment?.tappedResourceIds.count, 1, "prefer the single 3-gold resource")
        XCTAssertEqual(payment?.waste.gold, 0, "zero waste when paying exactly")
    }

    func testWasteCountedWhenOverpaying() {
        // Cost 2 gold. Only one 3-gold ready → must overpay, waste 1.
        let ready = [ res(ResourceAmount(food: 0, wood: 0, gold: 3)) ]
        let cost = ResourceAmount(food: 0, wood: 0, gold: 2)
        let payment = Economy.solve(cost: cost, ready: ready)
        XCTAssertNotNil(payment)
        XCTAssertEqual(payment?.waste.gold, 1, "1 gold wasted")
    }

    func testAntiGreedyCaseSubsetSearchResolves() {
        // Classic anti-greedy: cost needs 1 wood AND 1 gold.
        // Ready: A produces (1 wood, 0 gold), B produces (0 wood, 2 gold).
        // A greedy by total would tap B first (total 2 > 1) and then fail to
        // cover wood without also tapping A — but a correct solver covers with
        // {A, B} (waste 1 gold) which greedy-by-total also finds. The real
        // anti-greedy case: cost 1 wood + 2 gold.
        // Ready: A=(1 wood,0 gold), B=(0 wood,1 gold), C=(0 wood,1 gold).
        // Greedy-by-total picks A first, then B, then C → covers. But:
        // Ready: A=(2 wood), B=(2 gold). Cost = (1 wood, 1 gold).
        // Greedy-by-total (both total 2, tie → id order) picks A, covers wood
        // but then needs gold → picks B. OK. The genuinely tricky case is when
        // a high-total card would block a needed one. Construct it explicitly:
        let ready = [
            res(ResourceAmount(food: 0, wood: 2, gold: 0)), // A: 2 wood
            res(ResourceAmount(food: 0, wood: 0, gold: 2)), // B: 2 gold
            res(ResourceAmount(food: 0, wood: 1, gold: 1))  // C: 1+1 (total 2)
        ]
        let cost = ResourceAmount(food: 0, wood: 1, gold: 1)
        let payment = Economy.solve(cost: cost, ready: ready)
        XCTAssertEqual(payment?.tappedResourceIds.count, 1,
                       "C alone covers exactly; subset search should pick it over {A,B}")
        XCTAssertEqual(payment?.waste.total, 0)
    }

    func testImpossiblePaymentReturnsNil() {
        let ready = [ res(ResourceAmount(food: 0, wood: 0, gold: 1)) ]
        let cost = ResourceAmount(food: 0, wood: 0, gold: 5)
        XCTAssertNil(Economy.solve(cost: cost, ready: ready))
    }

    func testMultiDimensionalCost() {
        // 3 resources, each producing exactly 2 of one kind. Cost 2/2/2 means
        // each resource covers exactly its dimension with no surplus.
        let ready = [
            res(ResourceAmount(food: 2, wood: 0, gold: 0)),
            res(ResourceAmount(food: 0, wood: 2, gold: 0)),
            res(ResourceAmount(food: 0, wood: 0, gold: 2))
        ]
        let cost = ResourceAmount(food: 2, wood: 2, gold: 2)
        let payment = Economy.solve(cost: cost, ready: ready)
        XCTAssertEqual(payment?.tappedResourceIds.count, 3)
        XCTAssertEqual(payment?.waste.total, 0, "exact coverage → no waste")
    }

    func testFreeCostTapsNothing() {
        let ready = [ res(ResourceAmount(food: 1, wood: 1, gold: 1)) ]
        let payment = Economy.solve(cost: .zero, ready: ready)
        XCTAssertEqual(payment?.tappedResourceIds.count, 0)
        XCTAssertEqual(payment?.waste.total, 0)
    }

    func testMultiDimensionalWasteAcrossKinds() {
        // Each resource produces 3 of one kind; cost 2/2/2 → 1 wasted per kind.
        let ready = [
            res(ResourceAmount(food: 3, wood: 0, gold: 0)),
            res(ResourceAmount(food: 0, wood: 3, gold: 0)),
            res(ResourceAmount(food: 0, wood: 0, gold: 3))
        ]
        let cost = ResourceAmount(food: 2, wood: 2, gold: 2)
        let payment = Economy.solve(cost: cost, ready: ready)
        XCTAssertEqual(payment?.tappedResourceIds.count, 3)
        XCTAssertEqual(payment?.waste, ResourceAmount(food: 1, wood: 1, gold: 1))
    }

    func testSolverPrefersFewerTapsAtEqualWaste() {
        // Two ways to cover 2 gold with 0 waste:
        //   (A) one 2-gold resource (1 tap)
        //   (B) two 1-gold resources (2 taps)
        // Solver must pick (A): fewer taps at equal waste.
        let ready = [
            res(ResourceAmount(gold: 2)),
            res(ResourceAmount(gold: 1)),
            res(ResourceAmount(gold: 1))
        ]
        let payment = Economy.solve(cost: ResourceAmount(gold: 2), ready: ready)
        XCTAssertEqual(payment?.tappedResourceIds.count, 1)
        XCTAssertEqual(payment?.waste.total, 0)
    }

    // MARK: - Commit (test 4: surplus is lost)

    func testCommitTapsResourcesAndRecordsWaste() {
        var player = PlayerState(index: 0, civilization: .mongoles,
                                 strongholdCardId: "s",
                                 strongWeak: StrongWeakResources(strong: .gold, weak: .wood),
                                 provinces: [],
                                 resources: [
                                   ResourceInPlay(cardId: "g1", production: ResourceAmount(gold: 3)),
                                   ResourceInPlay(cardId: "g2", production: ResourceAmount(gold: 2))
                                 ])
        let ready = player.readyResources
        let cost = ResourceAmount(gold: 2)
        let payment = Economy.solve(cost: cost, ready: ready)!
        var waste = ResourceAmount.zero
        Economy.commit(payment, into: &player, wasteSink: &waste)
        XCTAssertEqual(waste.gold, 0, "paying 2 with a 2-gold resource wastes nothing")
        XCTAssertEqual(player.resources.filter { $0.isReady }.count, 1,
                       "one resource tapped")
    }

    func testCommitAccumulatesWasteAcrossPayments() {
        var player = PlayerState(index: 0, civilization: .mongoles,
                                 strongholdCardId: "s",
                                 strongWeak: StrongWeakResources(strong: .gold, weak: .wood),
                                 provinces: [],
                                 resources: [
                                   ResourceInPlay(cardId: "a", production: ResourceAmount(gold: 3)),
                                   ResourceInPlay(cardId: "b", production: ResourceAmount(gold: 3))
                                 ])
        var waste = ResourceAmount.zero
        // Pay 2 gold → tap 'a' (3 gold), waste 1.
        let p1 = Economy.solve(cost: ResourceAmount(gold: 2),
                               ready: player.readyResources)!
        Economy.commit(p1, into: &player, wasteSink: &waste)
        // Pay 2 gold → tap 'b' (3 gold), waste 1.
        let p2 = Economy.solve(cost: ResourceAmount(gold: 2),
                               ready: player.readyResources)!
        Economy.commit(p2, into: &player, wasteSink: &waste)
        XCTAssertEqual(waste.gold, 2, "1 + 1 wasted across two payments")
    }

    // MARK: - REL-02: greedy fallback path coverage

    /// When `ready.count > 16`, `solve` MUST fall back to `greedySolve` (to
    /// avoid exponential 2^n enumeration) and return a valid Payment — not nil,
    /// not a crash. Before this test, the n>16 path had zero direct coverage.
    func testSolveFallsBackToGreedyForLargeBoards() {
        // 20 single-gold resources (n > 16 triggers greedySolve).
        let board = (0..<20).map { idx in
            ResourceInPlay(cardId: "gold_\(idx)",
                          production: ResourceAmount(gold: 1))
        }
        let cost = ResourceAmount(gold: 3)

        let payment = Economy.solve(cost: cost, ready: board)

        XCTAssertNotNil(payment, "greedy fallback must find a payment for 3 gold with 20 single-gold resources")
        XCTAssertEqual(payment?.tappedResourceIds.count, 3, "must tap exactly 3 resources")
        XCTAssertEqual(payment?.waste.gold, 0, "no waste when 3 single-gold resources cover cost 3 exactly")
    }

    /// The greedy fallback must return nil when the large board genuinely
    /// cannot cover the cost — same contract as the enumerate path.
    func testSolveGreedyReturnsNilForImpossibleLargeBoard() {
        // 20 resources that produce only gold, but cost needs wood.
        let board = (0..<20).map { idx in
            ResourceInPlay(cardId: "gold_\(idx)",
                          production: ResourceAmount(gold: 1))
        }
        let cost = ResourceAmount(wood: 1)

        let payment = Economy.solve(cost: cost, ready: board)
        XCTAssertNil(payment, "greedy fallback must return nil when cost cannot be covered")
    }
}
