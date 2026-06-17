import Foundation

/// Economy: production (with strong/weak modifiers) and resource payment.
///
/// Resources are spent by tapping producing cards; production does not float.
/// Surplus produced beyond the cost is wasted (tracked per resource kind).
public enum Economy {

    /// Apply strong/weak modifiers to a resource's printed production.
    /// Strong kind: +1; weak kind: -1 floored at 0. Returns the clamped amount.
    public static func adjustedProduction(_ printed: ResourceAmount,
                                          strongWeak: StrongWeakResources) -> ResourceAmount {
        var out = printed
        out.set(strongWeak.strong, out.get(strongWeak.strong) + 1)
        out.set(strongWeak.weak, max(0, out.get(strongWeak.weak) - 1))
        return out
    }

    /// Result of a successful payment: which resources were tapped and how much
    /// of each resource was wasted (produced but unspent).
    public struct Payment: Hashable, Sendable {
        public let tappedResourceIds: [UUID]
        public let waste: ResourceAmount

        public init(tappedResourceIds: [UUID], waste: ResourceAmount) {
            self.tappedResourceIds = tappedResourceIds
            self.waste = waste
        }
    }

    /// A single candidate subset of ready resources that can cover `cost`.
    private struct Candidate: Hashable {
        let indices: [Int]                  // sorted ascending
        let taps: Int
        let waste: Int
        let ids: [UUID]                     // for tie-break by id
    }

    /// Try to pay `cost` by tapping a subset of `ready` resources.
    ///
    /// Algorithm (deterministic, [FIX 2]):
    ///   1. Enumerate all `2^n` subsets of ready resources.
    ///   2. Keep only those whose summed production covers every component of
    ///      `cost`.
    ///   3. Rank by `(waste_total ASC, taps_count ASC, lexicographic_by_id ASC)`
    ///      and pick the first.
    ///   4. If none covers, return nil.
    ///   5. Safety cap: when n > 16, fall back to a greedy deterministic picker
    ///      to avoid exponential blow-up (should not happen in v0.6).
    public static func solve(cost: ResourceAmount, ready: [ResourceInPlay]) -> Payment? {
        if cost.isFree { return Payment(tappedResourceIds: [], waste: .zero) }
        let readyCount = ready.count
        if readyCount == 0 { return nil }

        // Safety fallback for pathologically large boards.
        if readyCount > 16 {
            return greedySolve(cost: cost, ready: ready)
        }

        let best = enumerateBestCover(cost: cost, ready: ready)
        guard let best = best else { return nil }
        let tapped = best.indices.map { ready[$0].id }
        let summed = sum(ready, indices: best.indices)
        let waste = ResourceAmount(
            food: max(0, summed.food - cost.food),
            wood: max(0, summed.wood - cost.wood),
            gold: max(0, summed.gold - cost.gold)
        )
        return Payment(tappedResourceIds: tapped, waste: waste)
    }

    /// Enumerate subsets, return the best (or nil if none covers).
    private static func enumerateBestCover(cost: ResourceAmount,
                                           ready: [ResourceInPlay]) -> Candidate? {
        let count = ready.count
        var best: Candidate?

        // Iterate over all bitmasks 1..(2^count - 1).
        for mask in 1..<(1 << count) {
            var indices: [Int] = []
            var sumFood = 0, sumWood = 0, sumGold = 0
            var bit = 0
            var bits = mask
            while bits != 0 {
                if bits & 1 == 1 {
                    indices.append(bit)
                    sumFood += ready[bit].production.food
                    sumWood += ready[bit].production.wood
                    sumGold += ready[bit].production.gold
                }
                bits >>= 1
                bit += 1
            }
            guard sumFood >= cost.food, sumWood >= cost.wood, sumGold >= cost.gold else {
                continue
            }
            let waste = (sumFood - cost.food) + (sumWood - cost.wood) + (sumGold - cost.gold)
            let ids = indices.map { ready[$0].id }
            let candidate = Candidate(indices: indices,
                                      taps: indices.count,
                                      waste: waste,
                                      ids: ids)
            if isBetter(candidate, than: best) {
                best = candidate
            }
        }
        return best
    }

    /// Candidate ranking: (waste ASC, taps ASC, ids lexicographic ASC).
    private static func isBetter(_ candidate: Candidate, than current: Candidate?) -> Bool {
        guard let current = current else { return true }
        if candidate.waste != current.waste { return candidate.waste < current.waste }
        if candidate.taps != current.taps { return candidate.taps < current.taps }
        // Lexicographic by UUID string for stable, deterministic ordering.
        let lhs = candidate.ids.map { $0.uuidString }.joined(separator: ",")
        let rhs = current.ids.map { $0.uuidString }.joined(separator: ",")
        return lhs < rhs
    }

    /// Deterministic greedy fallback (only for n > 16). Not optimal, but safe.
    private static func greedySolve(cost: ResourceAmount, ready: [ResourceInPlay]) -> Payment? {
        var remaining = cost
        var tapped: [UUID] = []
        var summed = ResourceAmount.zero
        // Order by descending total production then by id for determinism.
        let sorted = ready.sorted {
            if $0.production.total != $1.production.total {
                return $0.production.total > $1.production.total
            }
            return $0.id.uuidString < $1.id.uuidString
        }
        for resource in sorted {
            if remaining.isFree { break }
            summed += resource.production
            remaining.food -= resource.production.food
            remaining.wood -= resource.production.wood
            remaining.gold -= resource.production.gold
            tapped.append(resource.id)
        }
        if remaining.food > 0 || remaining.wood > 0 || remaining.gold > 0 {
            return nil
        }
        let waste = ResourceAmount(
            food: max(0, summed.food - cost.food),
            wood: max(0, summed.wood - cost.wood),
            gold: max(0, summed.gold - cost.gold)
        )
        return Payment(tappedResourceIds: tapped, waste: waste)
    }

    private static func sum(_ resources: [ResourceInPlay], indices: [Int]) -> ResourceAmount {
        var total = ResourceAmount.zero
        for idx in indices { total += resources[idx].production }
        return total
    }

    /// Commit a payment against a player state: tap the chosen resources and
    /// accumulate wasted resources into `wasteSink`.
    ///
    /// This is one of the three coordinated writers of `resources[].isReady`
    /// — see `PlayerState.readyAll` for the full invariant. It is the ONLY path
    /// that consumes resource readiness (tap-to-pay). (audit AF-02)
    public static func commit(_ payment: Payment, into player: inout PlayerState,
                              wasteSink: inout ResourceAmount) {
        let tapSet = Set(payment.tappedResourceIds)
        for index in player.resources.indices where tapSet.contains(player.resources[index].id) {
            player.resources[index].isReady = false
        }
        wasteSink += payment.waste
    }
}
