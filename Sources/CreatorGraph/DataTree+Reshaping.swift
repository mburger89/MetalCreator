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
