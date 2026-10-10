import CreatorKernel

/// The levels the graph panel shows (groups spec §6): the top level, or the inside of a group node entered from it,
/// and so on down. A level is named by the group nodes entered, each by its ID in the graph before it.
extension GraphContent {
    /// The graph reached by entering the group nodes `levels` from the top level (`.root` for none), or `nil` when a
    /// step isn't a group node of a definition that exists.
    public func path(entering levels: [NodeID]) -> GraphPath? {
        var path = GraphPath.root
        for id in levels {
            guard let node = graph(at: path)?.nodes[id], node.typeID == GroupNodes.groupTypeID,
                  let definition = node.inputValues[NodeSetting.group]?.groupID, definitions[definition] != nil else {
                return nil
            }
            path = .definition(definition)
        }
        return path
    }

    /// The longest start of `levels` that still exists: after Undo removes a group node, or an edit deletes the one
    /// entered, the panel falls back to the level around it.
    public func existingLevels(_ levels: [NodeID]) -> [NodeID] {
        var count = levels.count
        while count > 0, path(entering: Array(levels.prefix(count))) == nil { count -= 1 }
        return Array(levels.prefix(count))
    }

    /// `value`, if it is a remembered pick, as the graph at `levels` names faces: the tags it holds name nodes by the
    /// identities they're made under (`NodeID.scoped` of the instance path), and a pick stored in a definition names
    /// them as if the definition were the top level (`GroupScopes.identity`), so every instance reads it as its own
    /// (`EvaluationScope.naming`). A pick made in the viewport while a definition's inside is shown goes through
    /// here before it is stored. Tags naming nodes outside the level, and every other value, are unchanged.
    public func relativeToLevel(_ value: ConstantValue, levels: [NodeID]) -> ConstantValue {
        guard case .definition(let id)? = path(entering: levels), let inside = definitions[id]?.graph else { return value }
        var names: [NodeID: NodeID] = [:]
        for relative in GroupScopes.paths(in: inside, definitions: definitions, entered: [id]) {
            names[NodeID.scoped(levels + relative)] = GroupScopes.identity(relative)
        }
        return value.renamingTags(names)
    }
}
