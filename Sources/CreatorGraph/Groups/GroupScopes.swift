import CreatorKernel

/// The identities nodes evaluate under across a document's groups (groups spec §5, `NodeID.scoped`): the cache keeps
/// entries of these, picks name faces by them, and group commands rename picks when they change
/// (`GroupScopes+PickRenaming`).
enum GroupScopes {
    /// Every identity of the nodes inside group node `node`, at every depth, when `node` sits at instance path `path`
    /// (the group nodes above it). A definition met inside itself isn't entered again.
    static func inner(of node: Node, at path: [NodeID], definitions: [GroupID: GroupDefinition],
                      entered: [GroupID] = []) -> Set<NodeID> {
        guard node.typeID == GroupNodes.groupTypeID, let id = node.inputValues[NodeSetting.group]?.groupID,
              !entered.contains(id), let definition = definitions[id] else { return [] }
        let inside = path + [node.id]
        var ids: Set<NodeID> = []
        for innerNode in definition.graph.nodes.values {
            ids.insert(NodeID.scoped(inside + [innerNode.id]))
            ids.formUnion(inner(of: innerNode, at: inside, definitions: definitions, entered: entered + [id]))
        }
        return ids
    }

    /// Every path from `graph` to one of its nodes (`[node]`) or to a node inside its group nodes, at every depth
    /// (`[group node, …, inner node]`). A definition met inside itself isn't entered again.
    static func paths(in graph: Graph, definitions: [GroupID: GroupDefinition], entered: [GroupID] = []) -> [[NodeID]] {
        var found: [[NodeID]] = []
        for node in graph.nodes.values {
            found.append([node.id])
            guard node.typeID == GroupNodes.groupTypeID, let id = node.inputValues[NodeSetting.group]?.groupID,
                  !entered.contains(id), let definition = definitions[id] else { continue }
            found += paths(in: definition.graph, definitions: definitions, entered: entered + [id]).map { [node.id] + $0 }
        }
        return found
    }

    /// The identity of the node `path` reaches from a graph, as that graph's picks name it: its own ID for a node of
    /// the graph, else `NodeID.scoped(path)`. From the top level, this is the identity it evaluates under.
    static func identity(_ path: [NodeID]) -> NodeID {
        if path.count == 1, let only = path.first { return only }
        return NodeID.scoped(path)
    }
}
