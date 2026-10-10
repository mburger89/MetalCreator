import CreatorKernel

/// Which definitions place which (groups spec §4): the rule that no definition contains itself, directly or through
/// other groups, and which group nodes an edit to a definition reaches.
public enum GroupDependencies {
    /// The definitions placed directly in `graph`.
    public static func direct(_ graph: Graph) -> Set<GroupID> {
        Set(graph.nodes.values.compactMap { node in
            node.typeID == GroupNodes.groupTypeID ? node.inputValues[NodeSetting.group]?.groupID : nil
        })
    }

    /// Every definition `id`'s inside places, directly or through other groups.
    public static func transitive(_ id: GroupID, in definitions: [GroupID: GroupDefinition]) -> Set<GroupID> {
        var seen: Set<GroupID> = []
        var pending = Array(definitions[id].map { direct($0.graph) } ?? [])
        while let next = pending.popLast() {
            guard seen.insert(next).inserted else { continue }
            if let definition = definitions[next] { pending += direct(definition.graph) }
        }
        return seen
    }

    /// Whether a group node of `target` in the graph at `path` would make a definition contain itself.
    public static func wouldRecurse(placing target: GroupID, in path: GraphPath,
                                    definitions: [GroupID: GroupDefinition]) -> Bool {
        guard case .definition(let host) = path else { return false }
        return target == host || transitive(target, in: definitions).contains(host)
    }

    /// Every group node of `id`: the top level's first, then each definition's in ID order; by node ID within a graph.
    public static func instances(of id: GroupID, in content: GraphContent) -> [GroupInstance] {
        let graphs = [(GraphPath.root, content.graph)]
            + content.definitions.values.sorted { $0.id < $1.id }.map { (GraphPath.definition($0.id), $0.graph) }
        return graphs.flatMap { path, graph in
            graph.nodes.values
                .filter { $0.typeID == GroupNodes.groupTypeID && $0.inputValues[NodeSetting.group]?.groupID == id }
                .sorted { $0.id < $1.id }
                .map { GroupInstance(path: path, node: $0) }
        }
    }

    /// The top-level nodes whose results depend on definition `id`: group nodes of it, or of a definition placing it.
    public static func dependents(of id: GroupID, in content: GraphContent) -> Set<NodeID> {
        Set(content.graph.nodes.values.filter { node in
            guard node.typeID == GroupNodes.groupTypeID, let target = node.inputValues[NodeSetting.group]?.groupID else {
                return false
            }
            return target == id || transitive(target, in: content.definitions).contains(id)
        }.map(\.id))
    }
}
