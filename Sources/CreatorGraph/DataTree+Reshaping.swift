extension DataTree {
    /// The nesting cut down to `levels` levels of branches kept from the outside (0 gives one flat list); a tree with
    /// that many or fewer is unchanged. Items keep their order.
    public func flattened(keeping levels: Int) -> DataTree {
        let keep = max(levels, 0)
        if keep == 0 { return .list(items) }
        if keep >= depth - 1 { return self }
        return DataTree(depth: keep + 1, scalars: [], children: branches.map { $0.flattened(keeping: keep - 1) })
    }

    /// Every item in a branch of its own, one level deeper.
    public func grafted() -> DataTree {
        if depth == 1 { return DataTree(depth: 2, scalars: [], children: items.map { .list([$0]) }) }
        return DataTree(depth: depth + 1, scalars: [], children: branches.map { $0.grafted() })
    }

    /// Each list of items split into branches of `size` (the last may be shorter), one level deeper.
    /// `size` must be at least 1.
    public func partitioned(size: Int) -> DataTree {
        let size = max(size, 1)
        if depth == 1 {
            let chunks = stride(from: 0, to: items.count, by: size).map { start in
                DataTree.list(Array(items[start..<min(start + size, items.count)]))
            }
            return DataTree(depth: 2, scalars: [], children: chunks)
        }
        return DataTree(depth: depth + 1, scalars: [], children: branches.map { $0.partitioned(size: size) })
    }
}

extension DataTree {
    /// The item at `index` of every branch, one item per branch (none where the branch is shorter), keeping the
    /// nesting. `missing` counts the branches that had no such item.
    public func picking(itemAt index: Int) -> (tree: DataTree, missing: Int) {
        if depth == 1 {
            let picked = items.indices.contains(index) ? [items[index]] : []
            return (.list(picked), picked.isEmpty ? 1 : 0)
        }
        let picks = branches.map { $0.picking(itemAt: index) }
        let tree = DataTree(depth: depth, branches: picks.map(\.tree)) ?? .empty(depth: depth)
        return (tree, picks.reduce(0) { $0 + $1.missing })
    }
}
