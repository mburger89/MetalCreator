extension Field {
    /// The fields this one is made from, in order. No `default`: a new case must say what its operands are.
    public var children: [Field] {
        switch self {
        case .constant, .distance, .linearGradient, .radialGradient, .noise:
            []
        case .add(let a, let b), .multiply(let a, let b), .minimum(let a, let b), .maximum(let a, let b),
             .smoothMinimum(let a, let b, _):
            [a, b]
        case .remap(let field, _, _, _, _, _), .clamp(let field, _, _):
            [field]
        }
    }

    /// How many nodes the expression has (itself and everything under it).
    public var nodeCount: Int { 1 + children.reduce(0) { $0 + $1.nodeCount } }

    /// A rough memory cost for the evaluator's cache (fields spec §2.1): 64 plus 32 per node. An image source adds its
    /// image's bytes in 7b-2.
    public var estimatedBytes: Int { 64 + 32 * nodeCount }
}
