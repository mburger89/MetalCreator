extension DataTree {
    /// A tree of this shape holding `scalars` instead of its items, in order: the nesting, the empty branches and the
    /// depth stay, so a node can compute one value per item and give them back in the tree it was computed from. `nil`
    /// when `scalars` is not as long as `itemCount`.
    public func replacingItems(_ scalars: [Scalar]) -> DataTree? {
        guard scalars.count == itemCount else { return nil }
        var next = 0
        return rebuilt(from: scalars, next: &next)
    }

    private func rebuilt(from scalars: [Scalar], next: inout Int) -> DataTree {
        if depth == 1 {
            let taken = Array(scalars[next..<next + count])
            next += count
            return DataTree(depth: 1, scalars: taken, children: [], slots: slots)
        }
        var rebuiltBranches: [DataTree] = []
        for branch in branches {
            rebuiltBranches.append(branch.rebuilt(from: scalars, next: &next))
        }
        return DataTree(depth: depth, branches: rebuiltBranches) ?? .empty(depth: depth)
    }
}
