extension ImplicitSolid {
    /// The baked distances in the tree that were made from a solid and are where that solid is: what a lattice's Face mapping looks
    /// for the picked face on. A solid that was moved (Place) is not where it was baked, so nothing under a move counts.
    public var sourceBlocks: [DistanceBlocks] {
        switch self {
        case .baked(let blocks, _): blocks.source == nil ? [] : [blocks]
        case .moved: []
        default: children.flatMap(\.sourceBlocks)
        }
    }

    /// True when a part of the tree is a moved copy of a baked solid, so a face of it is no longer where the solid has it.
    public var holdsMovedSource: Bool {
        switch self {
        case .moved(let child, _): !child.sourceBlocksIgnoringMoves.isEmpty
        default: children.contains(where: \.holdsMovedSource)
        }
    }

    private var sourceBlocksIgnoringMoves: [DistanceBlocks] {
        if case .baked(let blocks, _) = self { return blocks.source == nil ? [] : [blocks] }
        return children.flatMap(\.sourceBlocksIgnoringMoves)
    }
}
