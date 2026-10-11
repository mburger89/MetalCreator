/// One item or list input as the expansion walks down it.
struct TreeCursor {
    enum State {
        case scalar(Scalar)
        case tree(DataTree)

        init(_ value: Value) {
            switch value {
            case .one(let scalar): self = .scalar(scalar)
            case .list(let scalars): self = .tree(.list(scalars))
            case .tree(let tree): self = .tree(tree)
            }
        }
    }

    var name: SocketName
    var access: SocketSpec.Access
    var state: State

    /// The levels still to step down before the node's own unit: the item of an item socket, the flat list of a
    /// list socket.
    var remaining: Int {
        guard case .tree(let tree) = state else { return 0 }
        return access == .list ? max(tree.depth - 1, 0) : tree.depth
    }

    /// A tree of depth 2 or more: it always matches from its outermost level. Singles and flat lists match
    /// only when they are the deepest input left.
    var isStructured: Bool {
        if case .tree(let tree) = state { tree.depth >= 2 } else { false }
    }

    /// The depth of the tree the input started as (0 for a single item).
    var treeDepth: Int {
        if case .tree(let tree) = state { tree.depth } else { 0 }
    }

    func steps(whenDeepest deepest: Int) -> Bool {
        remaining >= 1 && (remaining == deepest || isStructured)
    }

    var count: Int {
        if case .tree(let tree) = state { tree.count } else { 0 }
    }

    /// This input after stepping into entry `index` (the last one when `index` is past the end).
    func stepped(to index: Int) -> TreeCursor {
        guard case .tree(let tree) = state else { return self }
        let at = min(index, tree.count - 1)
        var next = self
        next.state = tree.depth == 1 ? .scalar(tree.items[at]) : .tree(tree.branches[at])
        return next
    }

    /// What the node sees when no level is left.
    var slot: NodeInputs.Slot {
        switch (access, state) {
        case (.item, .scalar(let scalar)): .item(scalar)
        case (.item, .tree(let tree)): .list(tree.items)  // Unreachable: an item socket's tree always steps.
        case (.list, .scalar(let scalar)): .list([scalar])
        case (.list, .tree(let tree)): .list(tree.items)
        case (.tree, .scalar(let scalar)): .tree(.list([scalar]))
        case (.tree, .tree(let tree)): .tree(tree)
        }
    }
}
