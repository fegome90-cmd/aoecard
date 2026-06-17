import Foundation

/// Translates `Effect` values into combat modifiers on a `CombatResolver.ActiveEffects`
/// and into game-state actions (untap, free incursion, etc.) on the player.
///
/// This is the ONLY place in the engine that maps effect ids to behavior — the
/// combat resolver and rules engine never branch on card names.
public struct EffectApplier {

    public init() {}

    /// Fold a list of effects (from a card's `effects:` + its abilities) into
    /// `ActiveEffects` for a single battle.
    public func accumulate(_ effects: [Effect], into active: inout CombatResolver.ActiveEffects) {
        for effect in effects {
            switch effect {
            case .cancelCharge:
                active.chargeCanceled = true
                active.appliedEffectIDs.append(effect.id.id)

            case .suppressKeyword(let kw, _):
                active.suppressedKeywords.insert(kw)
                active.appliedEffectIDs.append(effect.id.id)

            case .battleAttackBonus(let amount, let filter):
                // We only model a global attacker bonus here; trait filters are
                // resolved when the rules engine selects participating units.
                _ = filter
                active.attackerAttackBonus += amount
                active.appliedEffectIDs.append(effect.id.id)

            case .battleDefenseBonus(let amount, let filter):
                _ = filter
                active.defenderDefenseBonus += amount
                active.appliedEffectIDs.append(effect.id.id)

            case .provinceDefenseReduction(let amount, _):
                active.provinceDefenseReduction += amount
                active.appliedEffectIDs.append(effect.id.id)

            case .amphibFirstAttackerBonus(let amount):
                active.amphibFirstAttackerBonus += amount
                active.appliedEffectIDs.append(effect.id.id)

            // Effects that act on game state rather than combat modifiers are
            // handled by the rules engine (untap_units, untap_resources,
            // free_incursion, grant_garrison, reveal_tactics_top, command_*,
            // range_bonus, archer_bonus_vs_trait, generic_modifier). We record
            // their ids so they show up in stats; the rules engine dispatches
            // them separately.
            case .untapUnits, .untapResources, .freeIncursion, .grantGarrison,
                 .revealTacticsTop, .commandAttackBonus, .rangeBonus,
                 .archerBonusVsTrait, .genericModifier:
                active.appliedEffectIDs.append(effect.id.id)
            }
        }
    }
}
