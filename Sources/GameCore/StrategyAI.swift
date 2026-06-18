import Foundation

/// A decision the AI can take during a player's turn. Each carries the weight
/// drawn from the strategy's priorities plus a deterministic tie-break key.
public enum Action: Sendable {
    case playResource(cardId: String)
    case playUnit(cardId: String)
    case playBuilding(cardId: String)
    case playTechnology(cardId: String)
    case playSpecial(cardId: String)
    case playTactic(cardId: String)
    case assaultProvince(targetPlayerIndex: Int, provinceIndex: Int)
    case assaultDestiny(destinyIndex: Int)
    case incursion(targetPlayerIndex: Int)
    case pass

    /// Which strategy priority weight applies to this action.
    public var priorityKey: KeyPath<Strategy.Priorities, Double> {
        switch self {
        case .playResource:     return \.playResource
        case .playUnit:         return \.playUnit
        case .playBuilding:     return \.playBuilding
        case .playTechnology:   return \.playUnit    // technologies use playUnit weight
        case .playSpecial:      return \.playUnit
        case .playTactic:       return \.holdTactics // inverted below (high weight = play)
        case .assaultProvince:  return \.assault
        case .assaultDestiny:   return \.attackDestiny
        case .incursion:        return \.incursion
        case .pass:             return \.holdTactics
        }
    }
}

/// The StrategyAI evaluates the set of legal actions for the current player,
/// weights each by its strategy priority, applies deterministic jitter from the
/// RNG, and returns the highest-scoring action (or `.pass`).
public struct StrategyAI {
    public let strategy: Strategy

    public init(strategy: Strategy) { self.strategy = strategy }

    /// Choose the next action. `rng` is mutated so choices are deterministic
    /// across runs given the same seed.
    public func choose(state: GameState, player: PlayerState,
                       rng: inout RandomSource) -> Action {
        let actions = legalActions(state: state, player: player)
        if actions.isEmpty { return .pass }

        // Score each action: base weight + deterministic jitter in [-0.05, 0.05].
        var best: (action: Action, score: Double) = (actions[0], -1)
        for action in actions {
            let weight = strategy.priorities[keyPath: action.priorityKey]
            let jitter = (rng.nextDouble() - 0.5) * 0.1
            let score = weight + jitter
            if score > best.score { best = (action, score) }
        }
        return best.action
    }

    /// Enumerate actions the player can legally take AND afford right now.
    /// Cards that can't be paid for are excluded so the AI doesn't waste turns
    /// spinning on unpayable specials.
    func legalActions(state: GameState, player: PlayerState) -> [Action] {
        var out: [Action] = []
        let opponent = state.players[player.index == 0 ? 1 : 0]
        let ready = player.readyResources

        // Helper: can the player pay this card's cost right now?
        func canPay(_ card: Card) -> Bool {
            Economy.solve(cost: card.cost, ready: ready) != nil
        }

        // 1. Play cards from hand that we can afford.
        for id in player.empireHand {
            guard let card = state.card(for: id), canPay(card) else { continue }
            if card.limits.uniqueInPlay, player.units.contains(where: { $0.cardId == id }) {
                continue
            }
            switch card.type {
            case .resource:
                // Honor the one-resource-per-turn flag (M1-4). perform() already
                // rejects a second resource, so without this guard the AI keeps
                // choosing resources it can't deploy and burns the consecutive-
                // failure budget, ending the turn early and distorting simulations.
                // The legal-action producer and perform() must share one truth.
                if !player.hasDeployedResourceThisTurn {
                    out.append(.playResource(cardId: id))
                }
            case .unit:
                out.append(.playUnit(cardId: id))
            case .building:
                out.append(.playBuilding(cardId: id))
            case .technology:
                out.append(.playTechnology(cardId: id))
            case .special:
                out.append(.playSpecial(cardId: id))
            default:
                break
            }
        }
        for id in player.tacticsHand {
            guard let card = state.card(for: id) else { continue }
            if card.limits.uniqueInPlay, player.units.contains(where: { $0.cardId == id }) {
                continue
            }
            out.append(.playTactic(cardId: id))
        }

        // 2. Declare an assault on an opponent province, if we have ready units.
        if !player.units.filter({ $0.isReady }).isEmpty {
            for (idx, prov) in opponent.provinces.enumerated() where !prov.isBroken {
                if prov.isStronghold && !opponent.strongholdExposed { continue }
                out.append(.assaultProvince(targetPlayerIndex: opponent.index, provinceIndex: idx))
            }
            for (idx, destiny) in state.destinyMap.enumerated() where destiny.controller != player.index {
                out.append(.assaultDestiny(destinyIndex: idx))
            }
            out.append(.incursion(targetPlayerIndex: opponent.index))
        }

        return out
    }
}

extension GameState {
    /// Look up a card definition by id.
    public func card(for id: String) -> Card? { cardsById[id] }
}
