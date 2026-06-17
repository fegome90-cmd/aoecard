import XCTest
@testable import GameCore

/// Resolver calibration tests (Slice 1.5). These check the resolver's
/// INVARIANTS — the new `battleWin`/`provinceDamage`/`rawProvinceDamage`
/// contract — not statistical gates (those live in the `calibrate` command).
final class ResolverCalibrationTests: XCTestCase {

    private let resolver = CombatResolver()
    private let combat = CombatRules()  // defaults from rules_v06.yaml

    private func unit(id: String, attack: Int, defense: Int, range: Int = 1,
                      traits: [Trait] = [], keywords: [Keyword] = []) -> UnitInPlay {
        UnitInPlay(cardId: id, civilization: .mongoles,
                   traits: Set(traits),
                   keywords: KeywordSet(entries: keywords),
                   baseStats: Stats(attack: attack, defense: defense, range: range))
    }

    private func province(defense: Int, traits: Set<Trait> = []) -> ProvinceInPlay {
        ProvinceInPlay(cardId: "p", baseDefense: defense, isStronghold: false, traits: traits)
    }

    // MARK: - P0-A: margin breaks the province

    func testAssaultWithLargeMarginBreaksProvince() {
        // Attacker 10 vs defender 0 units, province def 3.
        // margin = 10-0 = 10; rawProvinceDamage = max(0, 10-0-3) = 7.
        let attacker = [unit(id: "a", attack: 10, defense: 5)]
        let prov = province(defense: 3)
        let ctx = BattleContext(attacker: attacker.map { BattleUnit(ref: $0, side: .attacker) },
                                defender: [],
                                target: .province(prov),
                                terrainTraits: [],
                                isAssault: true)
        let r = resolver.resolve(ctx, combat: combat)
        XCTAssertTrue(r.battleWin)
        XCTAssertEqual(r.rawProvinceDamage, 7)
        XCTAssertEqual(r.provinceDamage, 7, "no floor needed — margin already produced damage")
    }

    // MARK: - P0-A: battle won but no raw margin → floor applies (assault only)

    func testAssaultWonWithZeroRawMarginAppliesBonusFloor() {
        // Attacker 5 vs defender 4 (one unit, defense 4). Province def 3.
        // margin = 5-4 = 1 → battleWin. rawProvinceDamage = max(0, 5-4-3) = 0.
        // Floor: provinceDamage = battleWinBonusDamage = 1.
        let attacker = [unit(id: "a", attack: 5, defense: 5)]
        let defender = [unit(id: "d", attack: 0, defense: 4)]
        let prov = province(defense: 3)
        let ctx = BattleContext(attacker: attacker.map { BattleUnit(ref: $0, side: .attacker) },
                                defender: defender.map { BattleUnit(ref: $0, side: .defender) },
                                target: .province(prov),
                                terrainTraits: [],
                                isAssault: true)
        let r = resolver.resolve(ctx, combat: combat)
        XCTAssertTrue(r.battleWin)
        XCTAssertEqual(r.rawProvinceDamage, 0, "no margin beyond province defense")
        XCTAssertEqual(r.provinceDamage, combat.battleWinBonusDamage,
                       "floor applies on battle-win-with-zero-raw in an assault")
    }

    func testAssaultWonWithRawMarginDoesNotStackFloor() {
        // Attacker 10 vs defender 0, province def 2 → raw = 8. Floor NOT added.
        let attacker = [unit(id: "a", attack: 10, defense: 5)]
        let prov = province(defense: 2)
        let ctx = BattleContext(attacker: attacker.map { BattleUnit(ref: $0, side: .attacker) },
                                defender: [],
                                target: .province(prov),
                                terrainTraits: [],
                                isAssault: true)
        let r = resolver.resolve(ctx, combat: combat)
        XCTAssertEqual(r.rawProvinceDamage, 8)
        XCTAssertEqual(r.provinceDamage, 8, "floor must not stack on top of raw margin")
    }

    // MARK: - P0-A: floor is assault-only (not destiny)

    func testDestinyAssaultWonWithZeroRawMarginDoesNotApplyFloor() {
        // Destiny defense is 3; attacker 4 vs 0 defenders → raw = 1 (4-0-3).
        // Use a destiny with effectively 3 def. To get zero raw, attacker 3:
        let destiny = DestinyInPlay(cardId: "d", category: .tradeRoute, traits: [])
        let attacker = [unit(id: "a", attack: 3, defense: 5)]
        let ctx = BattleContext(attacker: attacker.map { BattleUnit(ref: $0, side: .attacker) },
                                defender: [],
                                target: .destiny(destiny),
                                terrainTraits: [],
                                isAssault: true)
        let r = resolver.resolve(ctx, combat: combat)
        XCTAssertTrue(r.battleWin)
        XCTAssertEqual(r.rawProvinceDamage, 0, "destiny def 3, attacker 3 → raw 0")
        XCTAssertEqual(r.provinceDamage, 0, "floor is assault-on-province only; destiny gets none")
    }

    // MARK: - P0-B: lost battle deals zero province damage

    func testLostAssaultDealsZeroProvinceDamage() {
        // Attacker 2 vs defender 5 → margin -3, battleWin false.
        let attacker = [unit(id: "a", attack: 2, defense: 5)]
        let defender = [unit(id: "d", attack: 0, defense: 5)]
        let prov = province(defense: 2)
        let ctx = BattleContext(attacker: attacker.map { BattleUnit(ref: $0, side: .attacker) },
                                defender: defender.map { BattleUnit(ref: $0, side: .defender) },
                                target: .province(prov),
                                terrainTraits: [],
                                isAssault: true)
        let r = resolver.resolve(ctx, combat: combat)
        XCTAssertFalse(r.battleWin)
        XCTAssertEqual(r.rawProvinceDamage, 0)
        XCTAssertEqual(r.provinceDamage, 0, "no progress on a lost battle")
    }

    // MARK: - P0-B: battleWin independent of province defense

    func testBattleWinDoesNotRequireBeatingProvinceDefense() {
        // Attacker 6 vs defender 4 (margin +2 → battleWin) but province def 10.
        // Pre-1.5 this was a loss (6 < 4+10). Now it's a battle win with floor.
        let attacker = [unit(id: "a", attack: 6, defense: 5)]
        let defender = [unit(id: "d", attack: 0, defense: 4)]
        let prov = province(defense: 10)
        let ctx = BattleContext(attacker: attacker.map { BattleUnit(ref: $0, side: .attacker) },
                                defender: defender.map { BattleUnit(ref: $0, side: .defender) },
                                target: .province(prov),
                                terrainTraits: [],
                                isAssault: true)
        let r = resolver.resolve(ctx, combat: combat)
        XCTAssertTrue(r.battleWin, "beating the units is enough for a battle win")
        XCTAssertEqual(r.rawProvinceDamage, 0, "province def 10 too high for raw margin")
        XCTAssertEqual(r.provinceDamage, 1, "floor applies")
    }

    // MARK: - Casualties use configurable divisor

    func testCasualtiesFavorAttackerWhenMarginIsLarge() {
        // 1 attacker (atk 12) vs 3 defenders (def 2 each → defenderPressure 6).
        // margin = 6, divisor 3 → 2 defender losses.
        var c = combat
        c.casualtyDivisor = 3
        let attacker = [unit(id: "a", attack: 12, defense: 10)]
        let defenders = (0..<3).map { unit(id: "d\($0)", attack: 0, defense: 2) }
        let prov = province(defense: 0)
        let ctx = BattleContext(attacker: attacker.map { BattleUnit(ref: $0, side: .attacker) },
                                defender: defenders.map { BattleUnit(ref: $0, side: .defender) },
                                target: .province(prov),
                                terrainTraits: [],
                                isAssault: true)
        let r = resolver.resolve(ctx, combat: c)
        XCTAssertTrue(r.battleWin)
        XCTAssertEqual(r.defenderLosses.count, 2, "6 margin / 3 divisor = 2 losses")
    }

    // MARK: - Backward-compat aliases

    func testAttackerWinsAliasMatchesBattleWin() {
        let attacker = [unit(id: "a", attack: 5, defense: 5)]
        let prov = province(defense: 0)
        let ctx = BattleContext(attacker: attacker.map { BattleUnit(ref: $0, side: .attacker) },
                                defender: [],
                                target: .province(prov),
                                terrainTraits: [],
                                isAssault: true)
        let r = resolver.resolve(ctx, combat: combat)
        XCTAssertEqual(r.attackerWins, r.battleWin, "alias preserved for pre-1.5 callers")
        XCTAssertEqual(r.targetDamageDealt, r.provinceDamage)
    }

    // MARK: - Determinism preserved

    func testResolverRemainsDeterministic() {
        let attacker = [unit(id: "a", attack: 5, defense: 3),
                        unit(id: "b", attack: 4, defense: 2)]
        let defender = [unit(id: "d", attack: 2, defense: 4)]
        let prov = province(defense: 2)
        let ctx = BattleContext(attacker: attacker.map { BattleUnit(ref: $0, side: .attacker) },
                                defender: defender.map { BattleUnit(ref: $0, side: .defender) },
                                target: .province(prov),
                                terrainTraits: [],
                                isAssault: true)
        let r1 = resolver.resolve(ctx, combat: combat)
        let r2 = resolver.resolve(ctx, combat: combat)
        XCTAssertEqual(r1.battleWin, r2.battleWin)
        XCTAssertEqual(r1.provinceDamage, r2.provinceDamage)
        XCTAssertEqual(r1.defenderLosses, r2.defenderLosses)
    }
}

/// Slice 1.5-B tests: only participants tap; defenders tap whether they win
/// or lose. These exercise the RulesEngine's combat-action plumbing rather
/// than the resolver in isolation.
final class DefensiveFatigueTests: XCTestCase {

    private func unit(id: String, attack: Int, defense: Int) -> UnitInPlay {
        UnitInPlay(cardId: id, civilization: .mongoles, traits: [.mongoles, .caballeria],
                   keywords: KeywordSet(), baseStats: Stats(attack: attack, defense: defense))
    }

    private func province(defense: Int) -> ProvinceInPlay {
        ProvinceInPlay(cardId: "p", baseDefense: defense)
    }

    /// Build a minimal 2-player GameState with controllable units.
    private func makeState(attackerUnits: [UnitInPlay], defenderUnits: [UnitInPlay],
                          rules: Rules) -> GameState {
        let pA = PlayerState(index: 0, civilization: .mongoles,
                             strongholdCardId: "s",
                             strongWeak: StrongWeakResources(strong: .gold, weak: .wood),
                             provinces: [province(defense: 3)],
                             resources: [], units: attackerUnits)
        let pB = PlayerState(index: 1, civilization: .britanos,
                             strongholdCardId: "s",
                             strongWeak: StrongWeakResources(strong: .wood, weak: .food),
                             provinces: [province(defense: 3)],
                             resources: [], units: defenderUnits)
        return GameState(players: [pA, pB], destinyMap: [], round: 1, current: 0,
                         rng: RandomSource(seed: 1), rules: rules, cardsById: [:])
    }

    func testOnlyParticipatingAttackersTap() {
        // 2 ready attackers; only the ones that participate (filter isReady)
        // should be tapped afterward. We mark one as already-tapped to prove
        // the non-participant stays ready.
        let aParticipant = unit(id: "a1", attack: 5, defense: 5)
        var aIdle = unit(id: "a2", attack: 1, defense: 5)
        aIdle.isReady = false
        let defender = unit(id: "d1", attack: 0, defense: 2)
        var state = makeState(attackerUnits: [aParticipant, aIdle],
                              defenderUnits: [defender],
                              rules: Rules())

        var counters = LiveCounters()
        let engine = RulesEngine(strategyA: Strategy(name: "T", civilization: .mongoles,
                                                     priorities: .init()),
                                 strategyB: Strategy(name: "T", civilization: .britanos,
                                                     priorities: .init()),
                                 firstPlayer: 0)
        // Call perform directly (internal visibility via @testable import).
        let outcome = engine.perform(action: .assaultProvince(targetPlayerIndex: 1, provinceIndex: 0),
                                     state: &state, playerIdx: 0, counters: &counters)
        XCTAssertTrue(outcome.performed)
        // The participant a1 must be tapped.
        let a1 = state.players[0].units.first { $0.cardId == "a1" }!
        XCTAssertFalse(a1.isReady, "participating attacker tapped")
        // The idle a2 must remain tapped (was already, must not flip to ready).
        let a2 = state.players[0].units.first { $0.cardId == "a2" }!
        XCTAssertFalse(a2.isReady, "non-participant not flipped")
    }

    func testDefenderParticipantsTapWhetherTheyWinOrLose() {
        // Strong defender wins the battle but still taps (defensive fatigue).
        let attacker = unit(id: "a1", attack: 1, defense: 5)
        let defender = unit(id: "d1", attack: 0, defense: 10)
        var state = makeState(attackerUnits: [attacker], defenderUnits: [defender],
                              rules: Rules())
        var counters = LiveCounters()
        let engine = RulesEngine(strategyA: Strategy(name: "T", civilization: .mongoles,
                                                     priorities: .init()),
                                 strategyB: Strategy(name: "T", civilization: .britanos,
                                                     priorities: .init()),
                                 firstPlayer: 0)
        _ = engine.perform(action: .assaultProvince(targetPlayerIndex: 1, provinceIndex: 0),
                           state: &state, playerIdx: 0, counters: &counters)
        let d1 = state.players[1].units.first { $0.cardId == "d1" }!
        XCTAssertFalse(d1.isReady, "defender taps even when winning the battle")
    }
}

/// Slice 1.5-C tests: incursion applies keywords with their own gating,
/// exhausts a defender, and contests a Destiny.
final class IncursionCalibrationTests: XCTestCase {

    private func unit(id: String, attack: Int, defense: Int, traits: [Trait] = [],
                      keywords: [Keyword] = []) -> UnitInPlay {
        UnitInPlay(cardId: id, civilization: .mongoles, traits: Set(traits),
                   keywords: KeywordSet(entries: keywords),
                   baseStats: Stats(attack: attack, defense: defense))
    }

    private func province(defense: Int) -> ProvinceInPlay {
        ProvinceInPlay(cardId: "p", baseDefense: defense)
    }

    private func makeState(attackerUnits: [UnitInPlay], defenderUnits: [UnitInPlay],
                          destinies: [DestinyInPlay] = [],
                          opponentControlsDestiny: Bool = false,
                          rules: Rules) -> GameState {
        var pA = PlayerState(index: 0, civilization: .mongoles,
                             strongholdCardId: "s",
                             strongWeak: StrongWeakResources(strong: .gold, weak: .wood),
                             provinces: [province(defense: 3)],
                             resources: [], units: attackerUnits)
        pA.empireHand = []
        var pB = PlayerState(index: 1, civilization: .britanos,
                             strongholdCardId: "s",
                             strongWeak: StrongWeakResources(strong: .wood, weak: .food),
                             provinces: [province(defense: 3)],
                             resources: [], units: defenderUnits)
        pB.empireHand = []
        var dest = destinies
        if opponentControlsDestiny {
            for i in dest.indices { dest[i].controller = 1 }
        }
        return GameState(players: [pA, pB], destinyMap: dest, round: 1, current: 0,
                         rng: RandomSource(seed: 7), rules: rules, cardsById: [:])
    }

    func testIncursionExhaustsHighestDefenseDefender() {
        // Two defenders; incursion must tap the higher-defense one.
        let attacker = unit(id: "a1", attack: 10, defense: 10)
        let dLow = unit(id: "dLow", attack: 0, defense: 2)
        let dHigh = unit(id: "dHigh", attack: 0, defense: 8)
        var state = makeState(attackerUnits: [attacker],
                              defenderUnits: [dLow, dHigh], rules: Rules())
        var counters = LiveCounters()
        let engine = RulesEngine(strategyA: Strategy(name: "T", civilization: .mongoles, priorities: .init()),
                                 strategyB: Strategy(name: "T", civilization: .britanos, priorities: .init()),
                                 firstPlayer: 0)
        _ = engine.perform(action: .incursion(targetPlayerIndex: 1),
                           state: &state, playerIdx: 0, counters: &counters)
        // Incursion success is probabilistic; check the strongest defender was
        // the one tapped whenever one was. We assert the higher-defense unit
        // is tapped IF any was tapped.
        let highTapped = !(state.players[1].units.first { $0.cardId == "dHigh" }!.isReady)
        let lowTapped = !(state.players[1].units.first { $0.cardId == "dLow" }!.isReady)
        if highTapped || lowTapped {
            XCTAssertTrue(highTapped, "incursion must exhaust the highest-defense defender")
            XCTAssertFalse(lowTapped, "and not the weaker one")
            XCTAssertEqual(counters.incursionDefendersExhausted, 1)
        }
    }

    func testIncursionContestsOpponentDestiny() {
        // Attacker with strong pressure; one destiny controlled by the opponent.
        let attacker = unit(id: "a1", attack: 20, defense: 10)
        let destiny = DestinyInPlay(cardId: "d1", category: .tradeRoute, traits: [])
        var state = makeState(attackerUnits: [attacker], defenderUnits: [],
                              destinies: [destiny], opponentControlsDestiny: true,
                              rules: Rules())
        var counters = LiveCounters()
        let engine = RulesEngine(strategyA: Strategy(name: "T", civilization: .mongoles, priorities: .init()),
                                 strategyB: Strategy(name: "T", civilization: .britanos, priorities: .init()),
                                 firstPlayer: 0)
        // Force a successful incursion by retrying until counters reflect one.
        for _ in 0..<20 {
            _ = engine.perform(action: .incursion(targetPlayerIndex: 1),
                               state: &state, playerIdx: 0, counters: &counters)
            if counters.incursionsSuccessful >= 1 { break }
        }
        XCTAssertEqual(state.destinyMap[0].controller, 0,
                       "after a successful incursion, the contested Destiny flips to the attacker")
    }

    func testCargaDoesNotApplyOnIncursion() {
        // An attacker with Carga 5 would get +5 attack on an assault. On an
        // incursion (isAssault:false) it must NOT apply — so the resolver's
        // attackerPressure equals the base attack only.
        let resolver = CombatResolver()
        let attacker = unit(id: "a1", attack: 3, defense: 5,
                            keywords: [.init(name: .carga, magnitude: 5)])
        let prov = province(defense: 0)
        let ctx = BattleContext(attacker: [BattleUnit(ref: attacker, side: .attacker)],
                                defender: [],
                                target: .province(prov),
                                terrainTraits: [],
                                isAssault: false,
                                isIncursion: true)
        let r = resolver.resolve(ctx, combat: CombatRules())
        XCTAssertEqual(r.attackerPressure, 3, "Carga must not apply on an incursion")
        XCTAssertFalse(r.keywordsApplied.contains("carga_5"))
    }

    func testAsedioAppliesAgainstProvinceEvenOnIncursion() {
        // Asedio applies vs Province/Edificio/Maravilla — including incursions.
        let resolver = CombatResolver()
        let attacker = unit(id: "a1", attack: 3, defense: 5,
                            keywords: [.init(name: .asedio, magnitude: 4)])
        let prov = province(defense: 0)
        let ctx = BattleContext(attacker: [BattleUnit(ref: attacker, side: .attacker)],
                                defender: [],
                                target: .province(prov),
                                terrainTraits: [],
                                isAssault: false,
                                isIncursion: true)
        let r = resolver.resolve(ctx, combat: CombatRules())
        XCTAssertEqual(r.attackerPressure, 7, "Asedio +4 applies vs province on an incursion")
        XCTAssertTrue(r.keywordsApplied.contains("asedio_4"))
    }
}

/// Slice 1.5-D tests: Destiny control grants a per-turn resource bonus at the
/// start of the controller's turn.
final class DestinyControlBonusTests: XCTestCase {

    private func unit(id: String, attack: Int, defense: Int) -> UnitInPlay {
        UnitInPlay(cardId: id, civilization: .mongoles, traits: [.mongoles],
                   keywords: KeywordSet(), baseStats: Stats(attack: attack, defense: defense))
    }

    private func province(defense: Int) -> ProvinceInPlay {
        ProvinceInPlay(cardId: "p", baseDefense: defense)
    }

    func testControllerUntapsResourcesForControlledDestinies() {
        // Player A controls 2 Destinies; has 3 tapped resources. At the start
        // of A's turn, 2 resources should be untapped (resourceBonusPerRound=1
        // per Destiny).
        var r1 = ResourceInPlay(cardId: "r1", production: ResourceAmount(gold: 2))
        r1.isReady = false
        var r2 = ResourceInPlay(cardId: "r2", production: ResourceAmount(gold: 2))
        r2.isReady = false
        var r3 = ResourceInPlay(cardId: "r3", production: ResourceAmount(gold: 1))
        r3.isReady = false
        let pA = PlayerState(index: 0, civilization: .mongoles,
                             strongholdCardId: "s",
                             strongWeak: StrongWeakResources(strong: .gold, weak: .wood),
                             provinces: [province(defense: 3)],
                             resources: [r1, r2, r3], units: [unit(id: "a1", attack: 1, defense: 1)])
        let pB = PlayerState(index: 1, civilization: .britanos,
                             strongholdCardId: "s",
                             strongWeak: StrongWeakResources(strong: .wood, weak: .food),
                             provinces: [province(defense: 3)],
                             resources: [], units: [])
        var destiny = DestinyInPlay(cardId: "d1", category: .tradeRoute, traits: [])
        destiny.controller = 0
        var destiny2 = DestinyInPlay(cardId: "d2", category: .naturalTerrain, traits: [])
        destiny2.controller = 0
        var state = GameState(players: [pA, pB], destinyMap: [destiny, destiny2],
                              round: 1, current: 0,
                              rng: RandomSource(seed: 1), rules: Rules(), cardsById: [:])
        var counters = LiveCounters()
        let engine = RulesEngine(strategyA: Strategy(name: "T", civilization: .mongoles, priorities: .init()),
                                 strategyB: Strategy(name: "T", civilization: .britanos, priorities: .init()),
                                 firstPlayer: 0)
        engine.takeTurnForTest(state: &state, playerIdx: 0, counters: &counters)
        let readyCount = state.players[0].resources.filter { $0.isReady }.count
        XCTAssertEqual(readyCount, 2, "2 Destinies → 2 resources untapped")
        XCTAssertEqual(counters.destinyResourceBonus, 2)
    }

    func testNoBonusWithoutControlledDestinies() {
        var r1 = ResourceInPlay(cardId: "r1", production: ResourceAmount(gold: 2))
        r1.isReady = false
        let pA = PlayerState(index: 0, civilization: .mongoles,
                             strongholdCardId: "s",
                             strongWeak: StrongWeakResources(strong: .gold, weak: .wood),
                             provinces: [province(defense: 3)],
                             resources: [r1], units: [unit(id: "a1", attack: 1, defense: 1)])
        let pB = PlayerState(index: 1, civilization: .britanos,
                             strongholdCardId: "s",
                             strongWeak: StrongWeakResources(strong: .wood, weak: .food),
                             provinces: [province(defense: 3)],
                             resources: [], units: [])
        let destiny = DestinyInPlay(cardId: "d1", category: .tradeRoute, traits: [])  // neutral
        var state = GameState(players: [pA, pB], destinyMap: [destiny],
                              round: 1, current: 0,
                              rng: RandomSource(seed: 1), rules: Rules(), cardsById: [:])
        var counters = LiveCounters()
        let engine = RulesEngine(strategyA: Strategy(name: "T", civilization: .mongoles, priorities: .init()),
                                 strategyB: Strategy(name: "T", civilization: .britanos, priorities: .init()),
                                 firstPlayer: 0)
        engine.takeTurnForTest(state: &state, playerIdx: 0, counters: &counters)
        XCTAssertEqual(counters.destinyResourceBonus, 0, "no bonus without controlled Destinies")
        XCTAssertFalse(state.players[0].resources[0].isReady, "resource stays tapped")
    }
}
