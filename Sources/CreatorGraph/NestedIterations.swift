/// The iterations of a tree broadcast: what each one sees, and how they nest (7a spec §2).
struct NestedIterations: Sendable {
    /// How the iterations group: a leaf is one run of the node (its index), a branch the runs of one branch.
    indirect enum Layout: Sendable {
        case leaf(Int)
        case branches([Layout])
    }

    /// The levels matched: the nesting of every output.
    let depth: Int
    let layout: Layout
    /// The slots of iteration `i`.
    let slots: [[SocketName: NodeInputs.Slot]]

    /// The outputs' tree: `results[i]` is what iteration `i` produced, joined in the innermost branches.
    func tree(of results: [[Scalar]]) -> DataTree {
        Self.tree(layout, depth: depth, results: results)
    }

    private static func tree(_ layout: Layout, depth: Int, results: [[Scalar]]) -> DataTree {
        guard case .branches(let children) = layout else { return .empty(depth: depth) }
        if depth <= 1 {
            return .list(children.flatMap { child -> [Scalar] in
                if case .leaf(let index) = child { results[index] } else { [] }
            })
        }
        let branches = children.map { tree($0, depth: depth - 1, results: results) }
        return DataTree(depth: depth, branches: branches) ?? .empty(depth: depth)
    }
}
