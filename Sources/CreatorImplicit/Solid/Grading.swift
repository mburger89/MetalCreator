import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// A setting that may vary over space: a blend radius, a shell thickness, an offset (implicit spec §3.3). The field is sampled
/// per point by the implicit's own evaluator, never through `FieldSampler`. Distances to a solid, face set or edge set need the
/// kernel, so each is baked beforehand (`GradingBaker`) into `baked`, which the evaluator looks up by target.
public struct Grading: Hashable, Sendable {
    /// A distance to a kernel target, baked on a grid.
    public struct Baked: Hashable, Sendable {
        public var target: DistanceTarget.Identity
        public var signed: Bool
        public var blocks: DistanceBlocks

        public init(target: DistanceTarget.Identity, signed: Bool, blocks: DistanceBlocks) {
            self.target = target
            self.signed = signed
            self.blocks = blocks
        }
    }

    public var field: Field
    public var baked: [Baked]
    /// Every value the field takes over the region it was made for (rigorous: `GradingBaker` adds the field's slope times the
    /// half-diagonal of its sampling cells to the extremes it found).
    public var range: ClosedRange<Double>
    /// A bound on how fast the field changes, in value per millimetre (`Field.slopeBound`).
    public var slope: Double

    public init(field: Field, baked: [Baked] = [], range: ClosedRange<Double>, slope: Double) {
        self.field = field
        self.baked = baked
        self.range = range
        self.slope = slope
    }

    /// The same value everywhere.
    public static func constant(_ value: Double) -> Grading {
        Grading(field: .constant(value), range: value...value, slope: 0)
    }

    /// The value when it is the same everywhere.
    public var constantValue: Double? {
        if case .constant(let value) = field { value } else { nil }
    }

    /// The largest absolute value.
    public var magnitude: Double { max(abs(range.lowerBound), abs(range.upperBound)) }

    /// The baked blocks for a distance leaf, if it was baked.
    public func blocks(for target: DistanceTarget.Identity, signed: Bool) -> DistanceBlocks? {
        baked.first { $0.target == target && $0.signed == signed }?.blocks
    }

    public var estimatedBytes: Int { field.estimatedBytes + baked.reduce(0) { $0 + $1.blocks.estimatedBytes } }
}
