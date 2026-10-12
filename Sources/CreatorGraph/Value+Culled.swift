extension Value {
    /// This value with a culled flat list's indices dropped: a plain `.list` of its items. For an item socket, which
    /// pairs items by their place in the list, so the gaps mean nothing to it. Any other value is returned as it is.
    var droppingCulls: Value {
        if case .tree(let tree) = self, tree.depth == 1 { .list(tree.items) } else { self }
    }
}
