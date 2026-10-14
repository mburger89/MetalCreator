import CreatorGeometry

extension ImplicitSolid {
    /// The solids this one is made from, in order. No `default`: a new case must say what its operands are.
    public var children: [ImplicitSolid] {
        switch self {
        case .sphere, .box, .cylinder, .baked, .isosurface:
            []
        case .moved(let child, _), .offset(let child, _), .shell(let child, _, _):
            [child]
        case .subtract(let children, _), .union(let children, _), .intersect(let children, _):
            children
        }
    }

    /// The settings that vary over space, in order.
    var gradings: [Grading] {
        switch self {
        case .sphere, .box, .cylinder, .moved, .baked:
            []
        case .subtract(_, let blend), .union(_, let blend), .intersect(_, let blend):
            [blend]
        case .offset(_, let distance):
            [distance]
        case .shell(_, let thickness, _):
            [thickness]
        case .isosurface(let grading, _, _, _):
            [grading]
        }
    }

    /// How many nodes the tree has (itself and everything under it).
    public var nodeCount: Int { 1 + children.reduce(0) { $0 + $1.nodeCount } }

    /// A rough memory cost (implicit spec §2.1): 64 plus 32 per node, plus the bytes of every baked block table and every field
    /// the settings hold.
    public var estimatedBytes: Int { 64 + 32 * nodeCount + heldBytes }

    private var heldBytes: Int {
        var own = gradings.reduce(0) { $0 + $1.estimatedBytes }
        if case .baked(let blocks, _) = self { own += blocks.estimatedBytes }
        return own + children.reduce(0) { $0 + $1.heldBytes }
    }
}
