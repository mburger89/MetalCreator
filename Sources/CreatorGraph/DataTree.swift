/// Nested lists to any depth (spec §2). A tree of depth 1 is a flat list; depth 2 is a list of branches, each a list
/// of items; and so on. Every branch at a level has the same depth, so a tree's depth is a single number, and a gap in
/// the numbering is an empty branch. Paths are derived from positions (`TreePath`), never stored.
public struct DataTree: Sendable {
    /// How many indices an item's path has: 1 for a flat list.
    public let depth: Int
    private let scalars: [Scalar]
    private let children: [DataTree]
    /// A flat list that has been culled: each item's index in its branch, strictly increasing. `nil` for a list that
    /// has not been (its items are 0, 1, 2…) and for every tree deeper than a list.
    let slots: [Int]?

    /// A flat list: a tree of depth 1.
    public static func list(_ scalars: [Scalar]) -> DataTree {
        DataTree(depth: 1, scalars: scalars, children: [])
    }

    /// A tree of `depth` (at least 1) with nothing in it.
    public static func empty(depth: Int) -> DataTree {
        depth <= 1 ? .list([]) : DataTree(depth: depth, scalars: [], children: [])
    }

    /// A tree whose branches are `branches`, each one level shallower than the result. `nil` for a depth under 2 or
    /// a branch of the wrong depth.
    public init?(depth: Int, branches: [DataTree]) {
        guard depth >= 2, branches.allSatisfy({ $0.depth == depth - 1 }) else { return nil }
        self.init(depth: depth, scalars: [], children: branches)
    }

    init(depth: Int, scalars: [Scalar], children: [DataTree], slots: [Int]? = nil) {
        self.depth = depth
        self.scalars = scalars
        self.children = children
        self.slots = slots
    }

    /// A flat list that has been culled: its items keep the indices `positions` gives them (one per item, none
    /// negative, strictly increasing), so item `k` is still `{positions[k]}` and the gaps are the items taken out.
    /// Unlike a plain list it is kept as culled even when `positions` happens to be 0, 1, 2…, because what was taken
    /// off its end must not come back. `nil` when `positions` doesn't fit the items.
    public static func culledList(_ scalars: [Scalar], at positions: [Int]) -> DataTree? {
        guard positions.count == scalars.count, positions.allSatisfy({ $0 >= 0 }),
              zip(positions, positions.dropFirst()).allSatisfy({ $0 < $1 }) else { return nil }
        return DataTree(depth: 1, scalars: scalars, children: [], slots: positions)
    }

    /// True when some branch has been culled, so its items' indices are the ones they had, not 0, 1, 2…
    public var isCulled: Bool { depth == 1 ? slots != nil : children.contains { $0.isCulled } }

    /// A flat list's items' indices in their branch: 0, 1, 2… unless it was culled. Empty for a deeper tree.
    public var itemPositions: [Int] { depth == 1 ? (slots ?? Array(scalars.indices)) : [] }

    /// The indices of a culled flat list; `nil` for a plain list and for a deeper tree.
    public var culledPositions: [Int]? { depth == 1 ? slots : nil }

    /// The branches of a tree deeper than a list; none for a list.
    public var branches: [DataTree] { children }

    /// The entries at the outermost level: a list's items, a deeper tree's branches.
    public var count: Int { depth == 1 ? scalars.count : children.count }

    /// Every item, branch by branch.
    public var items: [Scalar] { depth == 1 ? scalars : children.flatMap(\.items) }

    public var itemCount: Int { depth == 1 ? scalars.count : children.reduce(0) { $0 + $1.itemCount } }

    /// One branch holding items: its path (the item paths without their last index) and the items.
    public struct Leaf: Sendable {
        public var path: TreePath
        public var items: [Scalar]
        /// Each item's index in its branch: 0, 1, 2… unless the branch was culled, when the survivors keep the indices
        /// they had.
        public var positions: [Int]
        /// Whether the branch was culled (its `positions` are held, not counted).
        public var isCulled: Bool

        /// The full path of item `k` of this branch.
        public func itemPath(_ k: Int) -> TreePath { path.appending(positions[k]) }
    }

    /// The branches that hold items, in order. A flat list is one leaf at `{}`.
    public var leaves: [Leaf] { leaves(under: TreePath()) }

    private func leaves(under path: TreePath) -> [Leaf] {
        if depth == 1 { return [Leaf(path: path, items: scalars, positions: itemPositions, isCulled: slots != nil)] }
        return children.enumerated().flatMap { index, child in child.leaves(under: path.appending(index)) }
    }

    /// The subtree at a branch path: the list of a leaf branch when `path` has `depth - 1` indices, a deeper tree for
    /// a shorter one. `nil` when a step is out of range or the path is too long.
    public func branch(at path: TreePath) -> DataTree? {
        var current = self
        for index in path.indices {
            guard current.depth > 1, current.children.indices.contains(index) else { return nil }
            current = current.children[index]
        }
        return current
    }

    /// This tree with every item run through `transform`; `nil` when it fails for any item.
    public func mapItems(_ transform: (Scalar) -> Scalar?) -> DataTree? {
        if depth == 1 {
            let mapped = scalars.compactMap(transform)
            guard mapped.count == scalars.count else { return nil }
            return DataTree(depth: 1, scalars: mapped, children: [], slots: slots)
        }
        var mappedChildren: [DataTree] = []
        for child in children {
            guard let mapped = child.mapItems(transform) else { return nil }
            mappedChildren.append(mapped)
        }
        return DataTree(depth: depth, scalars: [], children: mappedChildren)
    }

    public var estimatedBytes: Int {
        depth == 1 ? scalars.reduce(16) { $0 + $1.estimatedBytes } : children.reduce(16) { $0 + $1.estimatedBytes }
    }
}
