extension DataTree {
    /// What `rebuildingLeaves` takes back for one branch: its new items, the index each one has in its branch (one per
    /// item), and whether the branch is culled (so those indices are kept as they are rather than counted).
    public typealias LeafRewrite = (items: [Scalar], positions: [Int], isCulled: Bool)

    /// The same nesting with every branch that holds items rewritten by `transform`, which gets the branch and its
    /// ordinal (0 for the first branch that holds items, 1 for the next, counting empty ones, and so on in tree order).
    /// Branches that are empty gaps stay as they are. A branch's ordinal is what the random nodes use as its stream.
    public func rebuildingLeaves(_ transform: (_ leaf: Leaf, _ ordinal: Int) -> LeafRewrite) -> DataTree {
        var ordinal = 0
        return rebuilt(under: TreePath(), ordinal: &ordinal, transform)
    }

    private func rebuilt(under path: TreePath, ordinal: inout Int,
                         _ transform: (_ leaf: Leaf, _ ordinal: Int) -> LeafRewrite) -> DataTree {
        if depth == 1 {
            let leaf = Leaf(path: path, items: items, positions: itemPositions, isCulled: isCulled)
            let rewritten = transform(leaf, ordinal)
            ordinal += 1
            guard rewritten.isCulled else { return .list(rewritten.items) }
            return DataTree.culledList(rewritten.items, at: rewritten.positions) ?? .list(rewritten.items)
        }
        var rebuiltBranches: [DataTree] = []
        for (index, branch) in branches.enumerated() {
            rebuiltBranches.append(branch.rebuilt(under: path.appending(index), ordinal: &ordinal, transform))
        }
        return DataTree(depth: depth, scalars: [], children: rebuiltBranches)
    }

    /// Culling (patterns spec §4: "culling keeps paths"): the same nesting with only the items `keep` accepts, `k` being
    /// the item's place in the branch it is in now. Survivors keep the indices they had, so a gap is left where an item
    /// was taken out and no later item moves; a branch that loses every item stays, empty. A branch that was culled
    /// before stays culled, and one that loses nothing is left as it was.
    public func keepingItems(where keep: (_ leaf: Leaf, _ ordinal: Int, _ k: Int) -> Bool) -> DataTree {
        rebuildingLeaves { leaf, ordinal in
            let kept = leaf.items.indices.filter { keep(leaf, ordinal, $0) }
            return (kept.map { leaf.items[$0] }, kept.map { leaf.positions[$0] }, leaf.isCulled || kept.count < leaf.items.count)
        }
    }

    /// The same nesting and the same indices with each item replaced by `transform(leaf, ordinal, k)`.
    public func mappingItems(_ transform: (_ leaf: Leaf, _ ordinal: Int, _ k: Int) -> Scalar) -> DataTree {
        rebuildingLeaves { leaf, ordinal in
            (leaf.items.indices.map { transform(leaf, ordinal, $0) }, leaf.positions, leaf.isCulled)
        }
    }
}
