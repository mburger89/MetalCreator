/// The app's one random generator (patterns spec §4: "always seeded"): SplitMix64, Steele, Lea and Flood, "Fast Splittable
/// Pseudorandom Number Generators" (OOPSLA 2014), in the public-domain form Sebastiano Vigna publishes. It is written out
/// here, never the system's generator, so a seed gives the same numbers on every machine and in every release; changing a
/// step below changes every random result in every saved file, so `SeededRandomTests` pins its output.
///
/// The algorithm: the state starts at the seed and every draw adds `step` to it, then scrambles it with `mix`. That makes
/// draw `k` a function of the seed and `k` alone, so `value(at:)` reaches any draw directly and the nodes draw by an item's
/// place, not by how many items came before: adding a branch or an item never reshuffles the others.
///
/// A purpose says which node is drawing. The plain generator starts at the seed itself; a purpose first mixes the seed with a
/// constant of its own (`mix(seed ^ salt)`), so two nodes given the same seed still draw unrelated numbers. The salts are part
/// of the contract like the algorithm: changing one changes every saved file's result for that node, and `SeededRandomTests`
/// pins them.
///
/// A stream is an independent run of draws for the same seed and purpose. Stream 0 starts at the (mixed) seed itself; stream `n`
/// starts at `mix(start + n × step)`. The nodes use a branch's number as its stream, so two branches don't repeat each other's numbers.
public struct SeededRandom: Sendable {
    /// 2⁶⁴ divided by the golden ratio, rounded to an odd number.
    public static let step: UInt64 = 0x9E37_79B9_7F4A_7C15

    /// Which node is drawing: the raw value is the salt mixed into the seed, the node's name in ASCII ending `_1`.
    public enum Purpose: UInt64, Sendable {
        /// The bare generator (the published SplitMix64 sequence for seed 0), for tests of the generator itself.
        case plain = 0
        /// Random Reduce: "Reduce_1".
        case reduce = 0x5265_6475_6365_5F31
        /// Random Values: "Values_1".
        case values = 0x5661_6C75_6573_5F31
        /// Jitter: "Jitter_1".
        case jitter = 0x4A69_7474_6572_5F31
        /// Noise Field: "FNoise_1".
        case fieldNoise = 0x464E_6F69_7365_5F31
        /// Cull by Field, Probability: "FCull__1".
        case fieldCull = 0x4643_756C_6C5F_5F31
        /// Field Scatter: "Scattr_1".
        case scatter = 0x5363_6174_7472_5F31
        /// Voronoi Lattice's built-in seeds: "Voronoi_".
        case voronoi = 0x566F_726F_6E6F_695F
    }

    private let start: UInt64

    /// Where draw 0 of this stream starts: draw `k` is `mix(streamStart + (k + 1) × step)`. A shader that draws the same numbers is
    /// given this and `step`.
    public var streamStart: UInt64 { start }
    private var drawn = 0

    public init(seed: Int, stream: Int = 0, purpose: Purpose = .plain) {
        var state = UInt64(truncatingIfNeeded: seed)
        if purpose != .plain { state = Self.mix(state ^ purpose.rawValue) }
        if stream != 0 { state = Self.mix(state &+ UInt64(truncatingIfNeeded: stream) &* Self.step) }
        start = state
    }

    /// SplitMix64's output function: two xor-shift-multiply rounds and a last xor-shift.
    public static func mix(_ value: UInt64) -> UInt64 {
        var z = value
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Draw `index` (counting from 0) of this stream.
    public func value(at index: Int) -> UInt64 {
        Self.mix(start &+ UInt64(truncatingIfNeeded: index &+ 1) &* Self.step)
    }

    /// The next draw of this stream.
    public mutating func next() -> UInt64 {
        defer { drawn += 1 }
        return value(at: drawn)
    }

    /// Draw `index` as a real in [0, 1): its top 53 bits over 2⁵³, so every value is exact in a `Double`.
    public func unit(at index: Int) -> Double {
        Double(value(at: index) >> 11) * 0x1p-53
    }

    /// Draw `index` as a whole number in 0 ..< `bound` (`bound` at least 1): the draw's high bits scaled to the bound
    /// (multiply-high, no division), whose bias is below `bound` / 2⁶⁴.
    public func below(_ bound: Int, at index: Int) -> Int {
        precondition(bound >= 1, "SeededRandom.below needs a bound of at least 1")
        return Int(value(at: index).multipliedFullWidth(by: UInt64(bound)).high)
    }
}
