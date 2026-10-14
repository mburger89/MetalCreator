extension Field {
    /// The fields this one is made from, in order. No `default`: a new case must say what its operands are.
    public var children: [Field] {
        switch self {
        case .constant, .distance, .linearGradient, .radialGradient, .noise, .image, .implicit:
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

    /// A rough memory cost for the evaluator's cache (fields spec §2.1): 64 plus 32 per node, plus the bytes of every image
    /// and every implicit solid the expression holds.
    public var estimatedBytes: Int { 64 + 32 * nodeCount + heldBytes }

    /// The pixels of every image leaf and the bytes of every implicit leaf under (and in) this expression.
    private var heldBytes: Int {
        var own = 0
        switch self {
        case .image(let image, _, _, _, _): own = image.byteCount
        case .implicit(let solid): own = solid.payload.estimatedBytes
        default: break
        }
        return own + children.reduce(0) { $0 + $1.heldBytes }
    }
}
