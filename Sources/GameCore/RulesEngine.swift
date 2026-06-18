import Foundation

/// Live per-game counters accumulated while a single match is played.
public struct LiveCounters: Sendable {
    public var incursionsDeclared = 0
    public var incursionsSuccessful = 0
    public var assaultsDeclared = 0
    public var assaultsSuccessful = 0
    public var reactionsPlayed = 0
    public var unitsDestroyed = 0
    public var cardsDrawn = 0
    public var cardsPlayed = 0
    public var strongholdAbilityUses = 0
    public var keywordUses = 0
    public var destinyControls = 0
    public var firstProvinceBrokenRound: Int? = nil

    // Slice 1.5 metrics.
    public var provinceDamageDealt = 0
    public var assaultBattleWinsWithZeroRawProvinceDamage = 0
    public var incursionDefendersExhausted = 0
    public var destinyResourceBonus = 0

    public init() {}
}

/// Runs a single game to completion. Pure value-type game state; the only
/// input to a match is the seed + the (deckA, strategyA, deckB, strategyB)
/// configuration. Output: a GameResult.
public struct RulesEngine {
    public let resolver = CombatResolver()
    public let effectApplier = EffectApplier()
    public let aiA: StrategyAI
    public let aiB: StrategyAI
    public let strategyAName: String
    public let strategyBName: String
    public let firstPlayer: PlayerIndex

    public init(strategyA: Strategy, strategyB: Strategy, firstPlayer: PlayerIndex) {
        self.aiA = StrategyAI(strategy: strategyA)
        self.aiB = StrategyAI(strategy: strategyB)
        self.strategyAName = strategyA.name
        self.strategyBName = strategyB.name
        self.firstPlayer = firstPlayer
    }

    /// Play the game until a win condition or maxRounds is reached.
    public func play(initialState: GameState) -> (GameResult, GameState) {
        var state = initialState
        var counters = LiveCounters()

        // Shuffle both decks for both players before drawing the opening hands.
        // This is deterministic given the seeded rng.
        for i in 0..<2 {
            state.rng.shuffle(&state.players[i].empireDeck)
            state.rng.shuffle(&state.players[i].tacticsDeck)
        }

        // Initial draws.
        for _ in 0..<state.rules.setup.startingEmpireHand {
            for i in 0..<2 {
                if let id = state.players[i].drawEmpire() { _ = id; counters.cardsDrawn += 1 }
            }
        }
        for _ in 0..<state.rules.setup.startingTacticsHand {
            for i in 0..<2 {
                if let id = state.players[i].drawTactics() { _ = id; counters.cardsDrawn += 1 }
            }
        }

        var current = firstPlayer
        var winner: Int? = nil
        var winCondition: WinCondition = .stall
        var roundsPlayed = 0

        while winner == nil && roundsPlayed < state.rules.victory.maxRounds {
            roundsPlayed += 1
            // Each player takes a turn this round.
            for turn in 0..<2 {
                let playerIdx = (current + turn) % 2
                state.setCurrent(playerIdx)
                takeTurn(state: &state, playerIdx: playerIdx, counters: &counters)
                if let w = checkVictory(state: state) {
                    winner = w
                    winCondition = .strongholdBroken
                    break
                }
            }
            if winner != nil { break }
            // End of round: ready all resources/units, alternate initiative.
            state.players[0].readyAll()
            state.players[1].readyAll()
            // Draw one card per deck for each player at end of round.
            for i in 0..<2 {
                if let _ = state.players[i].drawEmpire() { counters.cardsDrawn += 1 }
                if let _ = state.players[i].drawTactics() { counters.cardsDrawn += 1 }
            }
            state.alternateInitiative()
            current = state.current
        }

        let result = makeResult(state: state, winner: winner,
                                 winCondition: winner == nil ? .stall : winCondition,
                                 rounds: roundsPlayed, counters: counters)
        return (result, state)
    }

    // MARK: - Turn

    /// Run one player's turn. The player keeps taking actions until they pass,
    /// hit `maxActions`, or hit too many consecutive failures (to avoid loops
    /// when the AI keeps choosing unpayable cards).
    ///
    /// Internal (not private) so tests can exercise it via @testable import.
    func takeTurnForTest(state: inout GameState, playerIdx: Int,
                         counters: inout LiveCounters) {
        takeTurn(state: &state, playerIdx: playerIdx, counters: &counters)
    }

    private func takeTurn(state: inout GameState, playerIdx: Int,
                          counters: inout LiveCounters) {
        state.players[playerIdx].hasDeployedResourceThisTurn = false
        // Slice 1.5-D: at the start of the controller's turn, each Destiny they
        // control untaps one tapped resource (highest production, deterministic
        // tie-break). No card draw — economy only, per the agreed slice scope.
        applyDestinyControlBonus(state: &state, playerIdx: playerIdx, counters: &counters)

        let maxActions = 8
        var performed = 0
        var consecutiveFailures = 0
        let ai = playerIdx == 0 ? aiA : aiB
        while performed < maxActions && consecutiveFailures < 4 {
            let player = state.players[playerIdx]
            let action = ai.choose(state: state, player: player, rng: &state.rng)
            if case .pass = action { break }
            let outcome = perform(action: action, state: &state,
                                  playerIdx: playerIdx, counters: &counters)
            counters.keywordUses += outcome.keywordUses
            if outcome.strongholdUse { counters.strongholdAbilityUses += 1 }
            if outcome.performed {
                counters.cardsPlayed += 1
                performed += 1
                consecutiveFailures = 0
            } else {
                consecutiveFailures += 1
            }
            if !outcome.continueTurn { break }
        }
    }

    /// Slice 1.5-D: grant the per-turn resource bonus for controlled Destinies.
    /// Only fires when `bonusTiming == .startOfControllerRound` (the only mode
    /// wired in this slice). Untaps up to `resourceBonusPerRound` tapped
    /// resources per controlled Destiny, deterministically (highest production,
    /// then stable id tie-break).
    private func applyDestinyControlBonus(state: inout GameState, playerIdx: Int,
                                          counters: inout LiveCounters) {
        guard state.rules.destinyControl.bonusTiming == .startOfControllerRound else { return }
        let controlled = state.destinyMap.filter { $0.controller == playerIdx }.count
        guard controlled > 0 else { return }
        let bonusPerDestiny = max(0, state.rules.destinyControl.resourceBonusPerRound)
        let totalToUntap = controlled * bonusPerDestiny
        guard totalToUntap > 0 else { return }

        var untapped = 0
        // Rank tapped resources by production total desc, then STABLE INDEX asc.
        // The previous uuidString tie-break leaked non-determinism (audit REL-03).
        let ranked = state.players[playerIdx].resources.enumerated()
            .filter { !$0.element.isReady }
            .sorted { lhs, rhs in
                let lt = lhs.element.production.total
                let rt = rhs.element.production.total
                if lt != rt { return lt > rt }
                return lhs.offset < rhs.offset
            }
        for (idx, _) in ranked {
            guard untapped < totalToUntap else { break }
            state.players[playerIdx].resources[idx].isReady = true
            untapped += 1
            counters.destinyResourceBonus += 1
        }
    }

    /// Execute one action. Returns:
    /// - `performed`: whether the action had effect (counts toward cardsPlayed).
    /// - `continueTurn`: whether the player should keep taking actions.
    /// - `keywordUses`, `strongholdUse`: stat counters.
    ///
    /// A failed payment is NOT a turn-ender — the player keeps trying other
    /// actions. Only `.pass` or hitting `maxActions` ends the turn.
    ///
    /// Internal (not private) so tests can exercise individual actions via
    /// `@testable import GameCore`.
    @discardableResult
    func perform(action: Action, state: inout GameState, playerIdx: Int,
                 counters: inout LiveCounters)
                 -> (performed: Bool, continueTurn: Bool,
                     keywordUses: Int, strongholdUse: Bool) {
        var strongholdUse = false
        var player = state.players[playerIdx]

        switch action {
        case .playResource(let id):
            guard let card = state.card(for: id),
                  let handIndex = player.empireHand.firstIndex(of: id) else {
                return (false, true, 0, false)
            }
            guard !player.hasDeployedResourceThisTurn else {
                return (false, true, 0, false)
            }
            guard let payment = Economy.solve(cost: card.cost, ready: player.readyResources) else {
                return (false, true, 0, false)
            }
            var waste = state.wasteByPlayer[playerIdx]
            Economy.commit(payment, into: &player, wasteSink: &waste)
            state.wasteByPlayer[playerIdx] = waste
            player.empireHand.remove(at: handIndex)
            let printed = card.production ?? .zero
            let adjusted = Economy.adjustedProduction(printed, strongWeak: player.strongWeak)
            player.resources.append(ResourceInPlay(cardId: id, production: adjusted,
                                                    isReady: !card.entersTapped))
            player.hasDeployedResourceThisTurn = true
            state.players[playerIdx] = player
            return (true, true, 0, false)

        case .playUnit(let id):
            guard let card = state.card(for: id),
                  let handIndex = player.empireHand.firstIndex(of: id),
                  let payment = Economy.solve(cost: card.cost, ready: player.readyResources) else {
                return (false, true, 0, false)
            }
            var waste = state.wasteByPlayer[playerIdx]
            Economy.commit(payment, into: &player, wasteSink: &waste)
            state.wasteByPlayer[playerIdx] = waste
            player.empireHand.remove(at: handIndex)
            let unit = UnitInPlay(cardId: id, civilization: card.civilization,
                                  traits: card.traitSet, keywords: card.keywordSet,
                                  baseStats: card.stats ?? Stats(), isReady: true,
                                  costPaid: card.cost)
            player.units.append(unit)
            state.players[playerIdx] = player
            return (true, true, 0, false)

        case .playBuilding(let id), .playTechnology(let id), .playSpecial(let id):
            guard let card = state.card(for: id),
                  let handIndex = player.empireHand.firstIndex(of: id),
                  let payment = Economy.solve(cost: card.cost, ready: player.readyResources) else {
                return (false, true, 0, false)
            }
            var waste = state.wasteByPlayer[playerIdx]
            Economy.commit(payment, into: &player, wasteSink: &waste)
            state.wasteByPlayer[playerIdx] = waste
            player.empireHand.remove(at: handIndex)
            player.permanents.append(PermanentInPlay(cardId: id, type: card.type,
                                                     civilization: card.civilization,
                                                     traits: card.traitSet))
            state.players[playerIdx] = player
            return (true, true, 0, false)

        case .playTactic(let id):
            guard let card = state.card(for: id),
                  let handIndex = player.tacticsHand.firstIndex(of: id) else {
                return (false, true, 0, false)
            }
            player.tacticsHand.remove(at: handIndex)
            for effect in card.effects {
                switch effect {
                case .untapResources(let count, let produces):
                    var untapped = 0
                    for i in player.resources.indices where player.resources[i].isReady == false {
                        if let p = produces, player.resources[i].production.get(p) == 0 { continue }
                        player.resources[i].isReady = true
                        untapped += 1
                        if untapped >= count { break }
                    }
                    if untapped > 0 { strongholdUse = true }
                case .untapUnits(let count, let filter):
                    var untapped = 0
                    for i in player.units.indices where player.units[i].isReady == false {
                        if !filter.traits.matches(player.units[i].traits) { continue }
                        player.units[i].isReady = true
                        untapped += 1
                        if untapped >= count { break }
                    }
                    _ = filter
                case .revealTacticsTop:
                    break
                default:
                    break
                }
            }
            state.players[playerIdx] = player
            return (true, true, 0, strongholdUse)

        case .assaultProvince(let targetIdx, let provIdx):
            let attacker = state.players[playerIdx]
            guard provIdx < state.players[targetIdx].provinces.count,
                  !state.players[targetIdx].provinces[provIdx].isBroken else {
                return (false, true, 0, false)
            }
            // Capture participant ids BEFORE building BattleUnits, so we tap only
            // those that actually fought (Slice 1.5-B), not every unit on the side.
            let attackerParticipantIds = Set(attacker.units.filter { $0.isReady }.map { $0.id })
            let attackerUnits = attacker.units.filter { $0.isReady }.map {
                BattleUnit(ref: $0, side: .attacker)
            }
            guard !attackerUnits.isEmpty else { return (false, true, 0, false) }
            counters.assaultsDeclared += 1

            let opponent = state.players[targetIdx]
            let prov = opponent.provinces[provIdx]
            let defenderParticipantIds = Set(opponent.units.filter { $0.isReady }.map { $0.id })
            let defenderUnits = opponent.units.filter { $0.isReady }.map {
                BattleUnit(ref: $0, side: .defender)
            }

            var active = CombatResolver.ActiveEffects()
            accumulateActiveEffects(state: state, attackerIdx: playerIdx,
                                    terrain: prov.traits, into: &active)

            let ctx = BattleContext(attacker: attackerUnits, defender: defenderUnits,
                                    target: .province(prov), terrainTraits: prov.traits,
                                    isAssault: true)
            let result = resolver.resolve(ctx, effects: active, combat: state.rules.combat)
            counters.keywordUses += result.keywordsApplied.count

            var opp = opponent
            // Battle win is distinct from breaking the province (Slice 1.5-A).
            if result.battleWin {
                counters.assaultsSuccessful += 1
                if result.rawProvinceDamage == 0 {
                    counters.assaultBattleWinsWithZeroRawProvinceDamage += 1
                }
            }
            if result.provinceDamage > 0 {
                counters.provinceDamageDealt += result.provinceDamage
                opp.provinces[provIdx].applyDamage(result.provinceDamage)
                if opp.provinces[provIdx].isBroken, counters.firstProvinceBrokenRound == nil {
                    counters.firstProvinceBrokenRound = state.round
                }
            }
            if !result.attackerLosses.isEmpty {
                state.players[playerIdx].units.removeAll { result.attackerLosses.contains($0.id) }
                counters.unitsDestroyed += result.attackerLosses.count
            }
            if !result.defenderLosses.isEmpty {
                opp.units.removeAll { result.defenderLosses.contains($0.id) }
                counters.unitsDestroyed += result.defenderLosses.count
            }
            // Tap only the participants (Slice 1.5-B). Attackers always tap.
            // Defenders tap if `defenderParticipantsTapAfterBattle`, regardless
            // of who won — defending costs readiness within the round.
            for i in state.players[playerIdx].units.indices {
                if attackerParticipantIds.contains(state.players[playerIdx].units[i].id) {
                    state.players[playerIdx].units[i].isReady = false
                }
            }
            if state.rules.combat.defenderParticipantsTapAfterBattle {
                for i in opp.units.indices where defenderParticipantIds.contains(opp.units[i].id) {
                    opp.units[i].isReady = false
                }
            }
            state.players[targetIdx] = opp
            return (true, true, result.keywordsApplied.count, false)

        case .assaultDestiny(let destinyIdx):
            let attacker = state.players[playerIdx]
            guard destinyIdx < state.destinyMap.count else { return (false, true, 0, false) }
            let attackerParticipantIds = Set(attacker.units.filter { $0.isReady }.map { $0.id })
            let attackerUnits = attacker.units.filter { $0.isReady }.map {
                BattleUnit(ref: $0, side: .attacker)
            }
            guard !attackerUnits.isEmpty else { return (false, true, 0, false) }
            counters.assaultsDeclared += 1

            let destiny = state.destinyMap[destinyIdx]
            let ctx = BattleContext(attacker: attackerUnits, defender: [],
                                    target: .destiny(destiny), terrainTraits: destiny.traits,
                                    isAssault: true)
            let result = resolver.resolve(ctx, combat: state.rules.combat)
            counters.keywordUses += result.keywordsApplied.count
            if result.battleWin {
                counters.assaultsSuccessful += 1
                counters.destinyControls += 1
                state.destinyMap[destinyIdx].controller = playerIdx
            }
            // Tap only the participants that assaulted the destiny.
            for i in state.players[playerIdx].units.indices {
                if attackerParticipantIds.contains(state.players[playerIdx].units[i].id) {
                    state.players[playerIdx].units[i].isReady = false
                }
            }
            return (true, true, result.keywordsApplied.count, false)

        case .incursion(let targetIdx):
            let attacker = state.players[playerIdx]
            let readyUnits = attacker.units.filter { $0.isReady }
            guard !readyUnits.isEmpty else { return (false, true, 0, false) }
            counters.incursionsDeclared += 1

            var opp = state.players[targetIdx]
            let candidates = opp.provinces.enumerated().filter {
                !$0.element.isStronghold && !$0.element.isBroken
            }
            guard let (weakestIdx, weakest) = candidates.min(by: {
                $0.element.currentDefense < $1.element.currentDefense
            }) else { return (false, true, 0, false) }

            // Compute effective pressure via a BattleContext so attacker
            // keywords apply — each keyword respects its own gate (Carga only
            // on isAssault, Asedio only vs province, etc.). isIncursion:true,
            // isAssault:false ensures Carga never fires here.
            let attackerParticipantIds = Set(readyUnits.map { $0.id })
            let attackerBattleUnits = readyUnits.map { BattleUnit(ref: $0, side: .attacker) }
            let defenderBattleUnits = opp.units.filter { $0.isReady }.map {
                BattleUnit(ref: $0, side: .defender)
            }
            var active = CombatResolver.ActiveEffects()
            accumulateActiveEffects(state: state, attackerIdx: playerIdx,
                                    terrain: weakest.traits, into: &active)
            let incCtx = BattleContext(attacker: attackerBattleUnits,
                                       defender: defenderBattleUnits,
                                       target: .province(weakest),
                                       terrainTraits: weakest.traits,
                                       isAssault: false,
                                       isIncursion: true)
            let pressure: Int
            if state.rules.combat.incursionAppliesKeywords {
                let incResult = resolver.resolve(incCtx, effects: active, combat: state.rules.combat)
                pressure = incResult.attackerPressure
                counters.keywordUses += incResult.keywordsApplied.count
            } else {
                pressure = readyUnits.reduce(0) { $0 + $1.baseStats.attack }
            }

            let defenseThreshold = weakest.currentDefense
            let margin = max(0, pressure - defenseThreshold)
            let chance = min(state.rules.combat.incursionChanceCap,
                             state.rules.combat.incursionBaseChance
                                + state.rules.combat.incursionChanceSlope * Double(margin))
            if state.rng.nextBool(probability: chance) {
                counters.incursionsSuccessful += 1
                // Tempo: untap a gold-producing resource (Mongol flavor).
                if let idx = state.players[playerIdx].resources.firstIndex(where: {
                    $0.production.gold > 0 && !$0.isReady
                }) {
                    state.players[playerIdx].resources[idx].isReady = true
                    strongholdUse = true
                }
                // Damage the weakest outer province.
                opp.provinces[weakestIdx].applyDamage(1)
                counters.provinceDamageDealt += 1
                if opp.provinces[weakestIdx].isBroken, counters.firstProvinceBrokenRound == nil {
                    counters.firstProvinceBrokenRound = state.round
                }
                // Exhaust one ready defender (highest defense, deterministic tie-break).
                if state.rules.combat.incursionExhaustsDefender {
                    let candidate = opp.units.enumerated()
                        .filter { $0.element.isReady }
                        .max { lhs, rhs in
                            if lhs.element.baseStats.defense != rhs.element.baseStats.defense {
                                return lhs.element.baseStats.defense < rhs.element.baseStats.defense
                            }
                            // Stable tie-break: smallest array offset wins (was uuidString — audit REL-03).
                            return lhs.offset > rhs.offset
                        }
                    if let (dIdx, _) = candidate {
                        opp.units[dIdx].isReady = false
                        counters.incursionDefendersExhausted += 1
                    }
                }
                // Contest/transfer a Destiny controlled by the opponent (or neutral).
                if state.rules.combat.incursionContestsDestiny {
                    let target = state.destinyMap.firstIndex {
                        $0.controller == targetIdx || $0.controller == nil
                    }
                    if let di = target {
                        state.destinyMap[di].controller = playerIdx
                        counters.destinyControls += 1
                    }
                }
            }
            // Tap half the ready attackers (lighter strike than a full assault),
            // only the participants.
            var tapped = 0
            let toTap = max(1, readyUnits.count / 2)
            for i in state.players[playerIdx].units.indices {
                if attackerParticipantIds.contains(state.players[playerIdx].units[i].id)
                    && state.players[playerIdx].units[i].isReady {
                    state.players[playerIdx].units[i].isReady = false
                    tapped += 1
                    if tapped >= toTap { break }
                }
            }
            state.players[targetIdx] = opp
            return (true, true, 0, strongholdUse)

        case .pass:
            return (false, false, 0, false)
        }
    }

    /// Gather combat-relevant effects from permanents in play (buildings,
    /// technologies, specials that grant battle modifiers).
    private func accumulateActiveEffects(state: GameState, attackerIdx: Int,
                                         terrain: Set<Trait>,
                                         into active: inout CombatResolver.ActiveEffects) {
        let attacker = state.players[attackerIdx]
        for perm in attacker.permanents {
            guard let card = state.cardsById[perm.cardId] else { continue }
            effectApplier.accumulate(card.effects, into: &active)
            for ability in card.abilities {
                effectApplier.accumulate(ability.effects, into: &active)
            }
        }
    }

    // MARK: - Victory / result

    /// Returns the winner's index (0 or 1) if someone has won, else nil.
    private func checkVictory(state: GameState) -> Int? {
        for i in 0..<2 {
            let opp = state.players[i == 0 ? 1 : 0]
            // Stronghold province must be broken AND exposed.
            if let sp = opp.provinces.first(where: { $0.isStronghold }),
               sp.isBroken, opp.strongholdExposed {
                return i
            }
        }
        return nil
    }

    private func makeResult(state: GameState, winner: Int?,
                            winCondition: WinCondition, rounds: Int,
                            counters: LiveCounters) -> GameResult {
        let civA = state.players[0].civilization
        let civB = state.players[1].civilization
        let waste = state.wasteByPlayer.reduce(ResourceAmount.zero) { $0 + $1 }
        return GameResult(
            matchup: "\(civA.label) vs \(civB.label)",
            civilizationA: civA, civilizationB: civB,
            strategyA: strategyAName, strategyB: strategyBName,
            winner: winner, winCondition: winCondition,
            rounds: rounds, firstPlayer: firstPlayer,
            firstProvinceBrokenRound: counters.firstProvinceBrokenRound,
            resourcesWastedFood: waste.food,
            resourcesWastedWood: waste.wood,
            resourcesWastedGold: waste.gold,
            deadCardsCount: 0, deadTurns: 0,
            destinyControls: counters.destinyControls,
            incursionsDeclared: counters.incursionsDeclared,
            incursionsSuccessful: counters.incursionsSuccessful,
            assaultsDeclared: counters.assaultsDeclared,
            assaultsSuccessful: counters.assaultsSuccessful,
            reactionsPlayed: counters.reactionsPlayed,
            unitsDestroyed: counters.unitsDestroyed,
            cardsDrawn: counters.cardsDrawn,
            cardsPlayed: counters.cardsPlayed,
            strongholdAbilityUses: counters.strongholdAbilityUses,
            keywordUses: counters.keywordUses,
            seed: state.rng.seed,
            provinceDamageDealt: counters.provinceDamageDealt,
            assaultBattleWinsWithZeroRawProvinceDamage: counters.assaultBattleWinsWithZeroRawProvinceDamage,
            incursionDefendersExhausted: counters.incursionDefendersExhausted,
            destinyResourceBonus: counters.destinyResourceBonus
        )
    }
}
