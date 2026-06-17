import Foundation

/// A unit's combat-relevant identity within a battle: who it is, what side,
/// and the modifiers applied so far (start at base stats).
public struct BattleUnit: Hashable, Sendable {
    public let ref: UnitInPlay              // snapshot reference (id)
    public let side: BattleSide
    public var traits: Set<Trait>
    public var keywords: KeywordSet
    public var attack: Int                  // current effective attack
    public var defense: Int                 // current effective defense
    public var range: Int                   // current effective range
    public var damageTaken: Int
    /// True when the unit has already tapped/acted this round.
    public var isReady: Bool

    public init(ref: UnitInPlay, side: BattleSide) {
        self.ref = ref
        self.side = side
        self.traits = ref.traits
        self.keywords = ref.keywords
        self.attack = ref.baseStats.attack
        self.defense = ref.baseStats.defense
        self.range = ref.baseStats.range
        self.damageTaken = ref.damage
        self.isReady = ref.isReady
    }

    public var isAlive: Bool { damageTaken < defense }
}

/// What kind of target the battle is against.
public enum BattleTarget: Hashable, Sendable {
    case province(ProvinceInPlay)           // assault on a province
    case destiny(DestinyInPlay)             // assault on a destiny card
}

/// Description of one battle: participants, target, terrain, and type.
public struct BattleContext: Sendable {
    public var attacker: [BattleUnit]
    public var defender: [BattleUnit]
    public var target: BattleTarget
    public var terrainTraits: Set<Trait>    // terrain of the battle location
    public var isAssault: Bool              // true = Asalto vs Province/Stronghold
    public var isIncursion: Bool            // true = Incursión (lighter strike)

    public init(attacker: [BattleUnit], defender: [BattleUnit],
                target: BattleTarget, terrainTraits: Set<Trait>,
                isAssault: Bool = false, isIncursion: Bool = false) {
        self.attacker = attacker
        self.defender = defender
        self.target = target
        self.terrainTraits = terrainTraits
        self.isAssault = isAssault
        self.isIncursion = isIncursion
    }

    /// Defense value the battle must overcome for each target type.
    ///
    /// Destinies use a fixed abstract defense in v0.6 (no province-style HP).
    /// The magic number is extracted as a named constant rather than a dead
    /// `? 3 : 3` branch (audit AF-05). If/when destiny defense becomes
    /// data-driven, replace this with a lookup into the destiny definition.
    public static let destinyAbstractDefense = 3

    public var targetDefense: Int {
        switch target {
        case .province(let prov): return prov.currentDefense
        case .destiny: return Self.destinyAbstractDefense
        }
    }

    public var isWaterTerrain: Bool { !terrainTraits.isDisjoint(with: Trait.waterTerrains) }
}

/// Result of resolving one battle.
public struct BattleResult: Sendable {
    public var attackerPressure: Int
    public var defenderPressure: Int
    public var margin: Int                  // attackerPressure - defenderPressure
    /// Tactical victory: the attacker beat the defending units. Distinct from
    /// breaking the province/destiny (see `provinceDamage`).
    public var battleWin: Bool
    /// Province damage from the raw margin formula
    /// (`max(0, attackerPressure - defenderPressure - targetDef)`), BEFORE the
    /// `battleWinBonusDamage` floor is applied. Used to detect "won the battle
    /// but only the floor produced progress".
    public var rawProvinceDamage: Int
    /// Final damage pushed onto the target province/destiny (margin damage +
    /// the `battleWinBonusDamage` floor when applicable). Alias kept for the
    /// pre-1.5 callers.
    public var provinceDamage: Int
    public var attackerLosses: [UUID]       // destroyed attacker units
    public var defenderLosses: [UUID]       // destroyed defender units
    public var initiativeDamageDealt: Int   // pre-pressure damage from Iniciativa
    public var keywordsApplied: [String]    // for stats tracking
    public var effectsApplied: [String]     // for stats tracking

    /// Pre-1.5 alias.
    public var attackerWins: Bool { battleWin }
    /// Pre-1.5 alias.
    public var targetDamageDealt: Int { provinceDamage }

    public init(attackerPressure: Int = 0, defenderPressure: Int = 0, margin: Int = 0,
                battleWin: Bool = false, rawProvinceDamage: Int = 0, provinceDamage: Int = 0,
                attackerLosses: [UUID] = [], defenderLosses: [UUID] = [],
                initiativeDamageDealt: Int = 0, keywordsApplied: [String] = [],
                effectsApplied: [String] = []) {
        self.attackerPressure = attackerPressure
        self.defenderPressure = defenderPressure
        self.margin = margin
        self.battleWin = battleWin
        self.rawProvinceDamage = rawProvinceDamage
        self.provinceDamage = provinceDamage
        self.attackerLosses = attackerLosses
        self.defenderLosses = defenderLosses
        self.initiativeDamageDealt = initiativeDamageDealt
        self.keywordsApplied = keywordsApplied
        self.effectsApplied = effectsApplied
    }
}

/// Resolves battles deterministically by Pressure, applying keyword modifiers
/// and effect modifiers. No dice.
public struct CombatResolver {

    /// Active effects for this battle, accumulated from tactics/tech/abilities.
    public struct ActiveEffects: Sendable {
        public var chargeCanceled: Bool
        public var suppressedKeywords: Set<KeywordName>
        public var provinceDefenseReduction: Int
        public var attackerAttackBonus: Int  // applied to attackers matching a filter
        public var defenderDefenseBonus: Int
        public var amphibFirstAttackerBonus: Int
        public var appliedEffectIDs: [String]

        public init() {
            self.chargeCanceled = false
            self.suppressedKeywords = []
            self.provinceDefenseReduction = 0
            self.attackerAttackBonus = 0
            self.defenderDefenseBonus = 0
            self.amphibFirstAttackerBonus = 0
            self.appliedEffectIDs = []
        }
    }

    public init() {}

    /// Resolve a battle. `effects` is the set of tactic/tech/ability modifiers
    /// in play for this battle (collected by the rules engine beforehand).
    /// `combat` provides the calibration knobs (Slice 1.5).
    public func resolve(_ context: BattleContext,
                        effects: ActiveEffects = .init(),
                        combat: CombatRules = .init()) -> BattleResult {
        var attacker = context.attacker
        var defender = context.defender
        var keywordsApplied: [String] = []
        var initiativeDamage = 0

        // 1. Apply charge cancellation (e.g. Línea de Estacas).
        if effects.chargeCanceled {
            keywordsApplied.append("charge_canceled")
        }

        // 2. Apply persistent attack/defense bonuses from effects.
        if effects.attackerAttackBonus != 0 {
            for idx in attacker.indices { attacker[idx].attack += effects.attackerAttackBonus }
            keywordsApplied.append("attacker_attack_bonus_\(effects.attackerAttackBonus)")
        }
        if effects.defenderDefenseBonus != 0 {
            for idx in defender.indices { defender[idx].defense += effects.defenderDefenseBonus }
            keywordsApplied.append("defender_defense_bonus_\(effects.defenderDefenseBonus)")
        }

        // 3. Keyword-driven modifiers (deterministic order).
        //    a) Anfibio: +1 Ataque al primer atacante Anfibio si el terreno es agua.
        if context.isWaterTerrain {
            var amphibApplied = false
            for idx in attacker.indices where attacker[idx].keywords.has(.anfibio) && !amphibApplied {
                attacker[idx].attack += 1
                amphibApplied = true
                keywordsApplied.append("anfibio_attack")
            }
        }

        //    b) Iniciativa: 1 daño pre-Presión a una unidad enemiga con defensa <= ataque.
        for unit in attacker where unit.keywords.has(.iniciativa)
            && !effects.suppressedKeywords.contains(.iniciativa) {
            if let defIdx = defender.firstIndex(where: { $0.defense <= unit.attack }) {
                defender[defIdx].damageTaken += 1
                initiativeDamage += 1
                keywordsApplied.append("iniciativa")
                break
            }
        }

        //    c) Carga X: +X Ataque al asaltar (no defendiendo).
        if context.isAssault && !effects.chargeCanceled {
            for idx in attacker.indices {
                let mag = attacker[idx].keywords.magnitude(of: .carga)
                if mag > 0 {
                    attacker[idx].attack += mag
                    keywordsApplied.append("carga_\(mag)")
                }
            }
        }

        //    d) Anti-Caballería X: +X Defensa contra Caballería/Caballería Arquera.
        let attackerHasCavalry = attacker.contains {
            $0.traits.contains(.caballeria) || $0.traits.contains(.caballeriaArquera)
        }
        if attackerHasCavalry {
            for idx in defender.indices {
                let mag = defender[idx].keywords.magnitude(of: .antiCaballeria)
                if mag > 0 {
                    defender[idx].defense += mag
                    keywordsApplied.append("antiCaballeria_\(mag)")
                }
            }
        }

        //    e) Asedio X: +X Ataque vs Provincia / Edificio / Maravilla.
        //       Applies to any province-targeted battle (assault OR incursion),
        //       per Slice 1.5-E5: each keyword respects its own condition, and
        //       Asedio's condition is the target type, not the action type.
        let isProvinceOrBuildingTarget: Bool = {
            if case .province = context.target { return true }
            return false
        }()
        if isProvinceOrBuildingTarget {
            for idx in attacker.indices {
                let mag = attacker[idx].keywords.magnitude(of: .asedio)
                if mag > 0 {
                    attacker[idx].attack += mag
                    keywordsApplied.append("asedio_\(mag)")
                }
            }
        }

        //    f) Guarnecer X: +X Defensa defendiendo Provincia propia.
        if case .province = context.target {
            for idx in defender.indices {
                let mag = defender[idx].keywords.magnitude(of: .guarnecer)
                if mag > 0 {
                    defender[idx].defense += mag
                    keywordsApplied.append("guarnecer_\(mag)")
                }
            }
        }

        //    g) Alcance Superior: ventaja de alcance si el atacante supera el máximo defensor.
        let maxDefenderRange = defender.map { $0.range }.max() ?? 0
        let anyAttackerSuperior = attacker.contains {
            $0.keywords.has(.alcanceSuperior) && !effects.suppressedKeywords.contains(.alcanceSuperior)
                && $0.range > maxDefenderRange
        }
        if anyAttackerSuperior {
            for idx in attacker.indices where attacker[idx].keywords.has(.alcanceSuperior)
                && attacker[idx].range > maxDefenderRange {
                attacker[idx].attack += 1
                keywordsApplied.append("alcanceSuperior")
                break
            }
        }

        //    h) Mando: la presencia de un Líder con Mando da +2 Ataque a otra unidad del trait.
        //       (Modelado genérico via command_attack_bonus effect; handled below in effects section.)

        // 4. Apply accumulated effect bonuses (amphib first attacker, etc.).
        if effects.amphibFirstAttackerBonus != 0 && context.isWaterTerrain {
            var applied = false
            for idx in attacker.indices where attacker[idx].keywords.has(.anfibio) && !applied {
                attacker[idx].attack += effects.amphibFirstAttackerBonus
                applied = true
            }
        }

        // 5. Compute Pressure.
        let attackerPressure = attacker.filter { $0.isAlive }.reduce(0) { $0 + $1.attack }
        let defenderPressure = defender.filter { $0.isAlive }.reduce(0) { $0 + $1.defense }

        // 6. Effective province/destiny defense after reductions.
        var targetDef = context.targetDefense - effects.provinceDefenseReduction
        if targetDef < 0 { targetDef = 0 }

        // 7. Tactical victory: the attacker beats the defending units. The
        //    province defense no longer gates the BATTLE outcome — it gates
        //    how much damage reaches the province (Slice 1.5).
        let margin = attackerPressure - defenderPressure
        let battleWin = margin > 0

        // 8. Casualties (abstract): losers lose one unit per `casualtyDivisor`.
        let divisor = max(1, combat.casualtyDivisor)
        var attackerLosses: [UUID] = []
        var defenderLosses: [UUID] = []
        if battleWin {
            let lost = min(defender.count, max(0, margin) / divisor)
            defenderLosses = defender.prefix(lost).map { $0.ref.id }
        } else if margin < 0 {
            let deficit = -margin
            let lost = min(attacker.count, deficit / divisor)
            attackerLosses = attacker.prefix(lost).map { $0.ref.id }
        }

        // 9. Province damage = the offensive surplus beyond the defense.
        //    A battle win with zero raw surplus still gets the bonus floor, so
        //    a successful assault on a PROVINCE always leaves at least some
        //    progress. The floor does not apply to Destiny assaults (destinies
        //    flip on a single successful assault, not on accumulated damage).
        let rawProvinceDamage = combat.provinceDamageFromMargin
            ? max(0, attackerPressure - defenderPressure - targetDef)
            : (battleWin ? max(0, margin) : 0)
        var provinceDamage = rawProvinceDamage
        let isProvinceTarget: Bool = {
            if case .province = context.target { return true }
            return false
        }()
        if battleWin && provinceDamage == 0 && context.isAssault && isProvinceTarget {
            provinceDamage = max(0, combat.battleWinBonusDamage)
        }

        return BattleResult(
            attackerPressure: attackerPressure,
            defenderPressure: defenderPressure,
            margin: margin,
            battleWin: battleWin,
            rawProvinceDamage: rawProvinceDamage,
            provinceDamage: provinceDamage,
            attackerLosses: attackerLosses,
            defenderLosses: defenderLosses,
            initiativeDamageDealt: initiativeDamage,
            keywordsApplied: keywordsApplied,
            effectsApplied: effects.appliedEffectIDs
        )
    }
}
