import XCTest
@testable import GameCore

/// Keyword tests — each battle keyword is exercised against a minimal BattleContext.
/// These verify the numeric modifiers that the abstract combat resolver applies.
final class KeywordTests: XCTestCase {

    private let resolver = CombatResolver()
    private let applier = EffectApplier()

    private func unit(id: String, civ: Civilization = .mongoles, traits: [Trait] = [],
                      keywords: [Keyword] = [],
                      attack: Int = 1, defense: Int = 1, range: Int = 1) -> UnitInPlay {
        UnitInPlay(cardId: id, civilization: civ,
                   traits: Set(traits),
                   keywords: KeywordSet(entries: keywords),
                   baseStats: Stats(attack: attack, defense: defense, range: range))
    }

    private func province(defense: Int, isStronghold: Bool = false,
                          traits: Set<Trait> = []) -> ProvinceInPlay {
        ProvinceInPlay(cardId: "p", baseDefense: defense,
                       isStronghold: isStronghold, traits: traits)
    }

    // MARK: - Anfibio (test 5)

    func testAnfibioBonusInWaterTerrain() {
        let attacker = [unit(id: "a", traits: [.mapuches, .anfibio], keywords: [.init(name: .anfibio)],
                             attack: 3, defense: 3)]
        let target = province(defense: 3)
        let ctx = BattleContext(attacker: attacker.map { BattleUnit(ref: $0, side: .attacker) },
                                defender: [],
                                target: .province(target),
                                terrainTraits: [.rio],
                                isAssault: true)
        let r = resolver.resolve(ctx)
        XCTAssertTrue(r.attackerWins, "anfibio +1 in water → higher pressure")
        XCTAssertEqual(r.attackerPressure, 4, "anfibio gets +1 attack in water terrain")
        XCTAssertTrue(r.keywordsApplied.contains("anfibio_attack"))
    }

    func testAnfibioNoBonusInNonWaterTerrain() {
        let attacker = [unit(id: "a", traits: [.mapuches, .anfibio], keywords: [.init(name: .anfibio)],
                             attack: 3, defense: 3)]
        let target = province(defense: 0)
        let ctx = BattleContext(attacker: attacker.map { BattleUnit(ref: $0, side: .attacker) },
                                defender: [],
                                target: .province(target),
                                terrainTraits: [.llanura],
                                isAssault: true)
        let r = resolver.resolve(ctx)
        XCTAssertEqual(r.attackerPressure, 3, "anfibio: no bonus in plain terrain")
        XCTAssertFalse(r.keywordsApplied.contains("anfibio_attack"))
    }

    // MARK: - Alcance Superior (test 7)

    func testAlcanceSuperiorGivesBonusWhenOutrangingDefender() {
        let attacker = [unit(id: "a", traits: [.britanos, .arqueria],
                             keywords: [.init(name: .alcanceSuperior)],
                             attack: 2, defense: 2, range: 3)]
        let defender = [unit(id: "d", traits: [.mongoles, .caballeria],
                             attack: 2, defense: 2, range: 1)]
        let target = province(defense: 1)
        let ctx = BattleContext(attacker: attacker.map { BattleUnit(ref: $0, side: .attacker) },
                                defender: defender.map { BattleUnit(ref: $0, side: .defender) },
                                target: .province(target),
                                terrainTraits: [],
                                isAssault: true)
        let r = resolver.resolve(ctx)
        XCTAssertEqual(r.attackerPressure, 3, "alcance superior +1 when outranging")
        XCTAssertTrue(r.keywordsApplied.contains("alcanceSuperior"))
    }

    func testAlcanceSuperiorNoBonusWhenNotOutranging() {
        let attacker = [unit(id: "a", traits: [.britanos, .arqueria],
                             keywords: [.init(name: .alcanceSuperior)],
                             attack: 2, defense: 2, range: 1)]
        let defender = [unit(id: "d", traits: [.mongoles, .caballeria],
                             attack: 2, defense: 2, range: 2)]
        let target = province(defense: 1)
        let ctx = BattleContext(attacker: attacker.map { BattleUnit(ref: $0, side: .attacker) },
                                defender: defender.map { BattleUnit(ref: $0, side: .defender) },
                                target: .province(target),
                                terrainTraits: [],
                                isAssault: true)
        let r = resolver.resolve(ctx)
        XCTAssertEqual(r.attackerPressure, 2, "no bonus when not outranging")
        XCTAssertFalse(r.keywordsApplied.contains("alcanceSuperior"))
    }

    // MARK: - Iniciativa

    func testIniciativaDealsPrePressureDamage() {
        // Attacker has iniciativa attack 3; defender has defense 2 ≤ 3 → takes 1 dmg.
        let attacker = [unit(id: "a", traits: [.mongoles, .lider],
                             keywords: [.init(name: .iniciativa)],
                             attack: 3, defense: 5, range: 1)]
        let defender = [unit(id: "d", traits: [.mongoles, .infanteria],
                             attack: 0, defense: 2, range: 1)]
        let target = province(defense: 0)
        let ctx = BattleContext(attacker: attacker.map { BattleUnit(ref: $0, side: .attacker) },
                                defender: defender.map { BattleUnit(ref: $0, side: .defender) },
                                target: .province(target),
                                terrainTraits: [],
                                isAssault: true)
        let r = resolver.resolve(ctx)
        XCTAssertEqual(r.initiativeDamageDealt, 1)
        XCTAssertTrue(r.keywordsApplied.contains("iniciativa"))
    }

    // MARK: - Carga X

    func testCargaAppliesOnAssault() {
        let attacker = [unit(id: "a", traits: [.mongoles, .caballeria],
                             keywords: [.init(name: .carga, magnitude: 2)],
                             attack: 3, defense: 3)]
        let target = province(defense: 1)
        let ctx = BattleContext(attacker: attacker.map { BattleUnit(ref: $0, side: .attacker) },
                                defender: [],
                                target: .province(target),
                                terrainTraits: [],
                                isAssault: true)
        let r = resolver.resolve(ctx)
        XCTAssertEqual(r.attackerPressure, 5, "carga +2 on assault")
    }

    func testCargaDoesNotApplyWhenDefending() {
        let defender = [unit(id: "d", traits: [.mongoles, .caballeria],
                             keywords: [.init(name: .carga, magnitude: 2)],
                             attack: 3, defense: 3)]
        let target = province(defense: 5)
        let ctx = BattleContext(attacker: [],
                                defender: defender.map { BattleUnit(ref: $0, side: .defender) },
                                target: .province(target),
                                terrainTraits: [],
                                isAssault: true)
        let r = resolver.resolve(ctx)
        // No attackers → no pressure, no carga application.
        XCTAssertEqual(r.attackerPressure, 0)
        XCTAssertFalse(r.keywordsApplied.contains("carga_2"))
    }

    func testCargaCanceledByEffect() {
        var active = CombatResolver.ActiveEffects()
        applier.accumulate([.cancelCharge], into: &active)
        XCTAssertTrue(active.chargeCanceled)

        let attacker = [unit(id: "a", traits: [.mongoles, .caballeria],
                             keywords: [.init(name: .carga, magnitude: 2)],
                             attack: 3, defense: 3)]
        let target = province(defense: 1)
        let ctx = BattleContext(attacker: attacker.map { BattleUnit(ref: $0, side: .attacker) },
                                defender: [],
                                target: .province(target),
                                terrainTraits: [],
                                isAssault: true)
        let r = resolver.resolve(ctx, effects: active)
        XCTAssertEqual(r.attackerPressure, 3, "carga suppressed by cancel_charge")
    }

    // MARK: - Anti-Caballería X

    func testAntiCaballeriaAppliesAgainstCavalryAttacker() {
        let attacker = [unit(id: "a", traits: [.mongoles, .caballeria],
                             attack: 3, defense: 3)]
        let defender = [unit(id: "d", traits: [.mapuches, .lancero],
                             keywords: [.init(name: .antiCaballeria, magnitude: 2)],
                             attack: 2, defense: 3)]
        let target = province(defense: 1)
        let ctx = BattleContext(attacker: attacker.map { BattleUnit(ref: $0, side: .attacker) },
                                defender: defender.map { BattleUnit(ref: $0, side: .defender) },
                                target: .province(target),
                                terrainTraits: [],
                                isAssault: true)
        let r = resolver.resolve(ctx)
        XCTAssertEqual(r.defenderPressure, 5, "anti-cab +2 defense against cavalry")
    }

    // MARK: - Asedio X

    func testAsedioAppliesAgainstProvince() {
        let attacker = [unit(id: "a", traits: [.mongoles, .asedio],
                             keywords: [.init(name: .asedio, magnitude: 3)],
                             attack: 4, defense: 2)]
        let target = province(defense: 4)
        let ctx = BattleContext(attacker: attacker.map { BattleUnit(ref: $0, side: .attacker) },
                                defender: [],
                                target: .province(target),
                                terrainTraits: [],
                                isAssault: true)
        let r = resolver.resolve(ctx)
        XCTAssertEqual(r.attackerPressure, 7, "asedio +3 vs province")
    }

    // MARK: - Guarnecer X

    func testGuarnecerAppliesWhenDefendingProvince() {
        let attacker = [unit(id: "a", traits: [.mongoles, .caballeria],
                             attack: 4, defense: 3)]
        let defender = [unit(id: "d", traits: [.britanos, .guardia],
                             keywords: [.init(name: .guarnecer, magnitude: 2)],
                             attack: 2, defense: 5)]
        let target = province(defense: 1)
        let ctx = BattleContext(attacker: attacker.map { BattleUnit(ref: $0, side: .attacker) },
                                defender: defender.map { BattleUnit(ref: $0, side: .defender) },
                                target: .province(target),
                                terrainTraits: [],
                                isAssault: true)
        let r = resolver.resolve(ctx)
        XCTAssertEqual(r.defenderPressure, 7, "guarnecer +2 defense on province defense")
    }

    // MARK: - Province defense reduction effect

    func testProvinceDefenseReductionEffect() {
        var active = CombatResolver.ActiveEffects()
        applier.accumulate([.provinceDefenseReduction(amount: 2, condition: .any)], into: &active)
        XCTAssertEqual(active.provinceDefenseReduction, 2)

        let attacker = [unit(id: "a", traits: [.britanos, .arqueria],
                             attack: 5, defense: 2)]
        let target = province(defense: 4)
        let ctx = BattleContext(attacker: attacker.map { BattleUnit(ref: $0, side: .attacker) },
                                defender: [],
                                target: .province(target),
                                terrainTraits: [],
                                isAssault: true)
        let r = resolver.resolve(ctx, effects: active)
        // Province effective def = 4 - 2 = 2; attacker 5 > 2 → win with margin 3.
        XCTAssertTrue(r.attackerWins)
        XCTAssertEqual(r.targetDamageDealt, 3)
    }

    // MARK: - Única (test 9): handled in DeckTests/RulesEngine; here we verify
    // the card model exposes the flag correctly.

    func testUniqueInPlayFlagOnCard() throws {
        let locator = try DataLocator()
        let loader = CardLoader(locator: locator)
        let cards = try loader.loadAllCards()
        let khan = try XCTUnwrap(cards["mongol_khan_de_guerra"])
        XCTAssertTrue(khan.limits.uniqueInPlay, "Khan de Guerra is uniqueInPlay")
        XCTAssertEqual(khan.limits.maxCopiesInDeck, 1, "and capped to 1 copy in deck")
    }

    // MARK: - Determinism: same context → same result

    func testResolverIsDeterministic() {
        let attacker = [unit(id: "a", traits: [.mongoles, .caballeria],
                             keywords: [.init(name: .carga, magnitude: 1)],
                             attack: 4, defense: 3)]
        let defender = [unit(id: "d", traits: [.mapuches, .lancero],
                             keywords: [.init(name: .antiCaballeria, magnitude: 2)],
                             attack: 2, defense: 3)]
        let target = province(defense: 2)
        let ctx = BattleContext(attacker: attacker.map { BattleUnit(ref: $0, side: .attacker) },
                                defender: defender.map { BattleUnit(ref: $0, side: .defender) },
                                target: .province(target),
                                terrainTraits: [],
                                isAssault: true)
        let r1 = resolver.resolve(ctx)
        let r2 = resolver.resolve(ctx)
        XCTAssertEqual(r1.attackerPressure, r2.attackerPressure)
        XCTAssertEqual(r1.defenderPressure, r2.defenderPressure)
        XCTAssertEqual(r1.margin, r2.margin)
        XCTAssertEqual(r1.attackerWins, r2.attackerWins)
    }
}
