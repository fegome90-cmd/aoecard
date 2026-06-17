import Foundation

/// Deterministic PRNG for the simulator. Implements SplitMix64 (well-defined
/// across platforms) seeded by a `UInt64`. All randomness in the engine MUST
/// flow through this type so that a given seed reproduces a game bit-for-bit.
///
/// We deliberately do NOT use `SystemRandomNumberGenerator` (non-deterministic)
/// or `SipHash`-based generators tied to stdlib internals.
public struct RandomSource: Sendable {
    /// Internal state. Mutated on each draw.
    public private(set) var state: UInt64

    /// Seed that produced this source (for reproducibility logs).
    public let seed: UInt64

    public init(seed: UInt64) {
        self.seed = seed
        self.state = seed
    }

    /// Produce the next 64-bit pseudo-random value.
    public mutating func next() -> UInt64 {
        // SplitMix64 increment.
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z &>> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z &>> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z &>> 31)
    }

    /// Uniform integer in `0 ..< upperBound`. `upperBound` must be > 0.
    public mutating func nextInt(_ upperBound: Int) -> Int {
        precondition(upperBound > 0, "upperBound must be > 0")
        return Int(next() % UInt64(upperBound))
    }

    /// Uniform integer in the closed range `lower...upper`.
    public mutating func nextInt(in lower: Int, _ upper: Int) -> Int {
        precondition(upper >= lower, "upper must be >= lower")
        return lower + nextInt(upper - lower + 1)
    }

    /// Uniform double in `[0, 1)`.
    public mutating func nextDouble() -> Double {
        // 53 high bits of randomness scaled to [0,1).
        let high = next() >> 11
        return Double(high) / Double(1 << 53)
    }

    /// `true` with the given probability in `[0, 1]`.
    public mutating func nextBool(probability p: Double) -> Bool {
        nextDouble() < p
    }

    /// Shuffle the elements of the given array in place using Fisher–Yates.
    public mutating func shuffle<T>(_ array: inout [T]) {
        guard array.count > 1 else { return }
        for i in stride(from: array.count - 1, through: 1, by: -1) {
            let j = nextInt(i + 1)
            array.swapAt(i, j)
        }
    }

    /// Pick one element uniformly at random from a non-empty array.
    public mutating func pick<T>(_ array: [T]) -> T? {
        guard !array.isEmpty else { return nil }
        return array[nextInt(array.count)]
    }

    /// Fork into a stream derived deterministically from `tag`. Useful to give
    /// subsystems independent streams without inter-dependencies.
    public mutating func fork(_ tag: UInt64) -> RandomSource {
        var copy = self
        let mixed = copy.next() ^ tag &* 0x9E37_79B9_7F4A_7C15
        return RandomSource(seed: mixed)
    }
}
