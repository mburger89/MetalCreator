import CreatorKernel

extension GraphContent {
    /// Identity a face's tags name → node of the graph at `levelPath` (the group nodes entered, `[]` for the top level): the node's own
    /// identity there (its ID at the top, `NodeID.scoped(levelPath + [id])` inside), every identity inside a group node of that level
    /// (→ the group node), and each placer's copies, `NodeID.instanceScoped([identity(placer), identity(tool)])` for every node of the
    /// level as the tool and the placer itself (→ the placer).
    public func levelProducers(at levelPath: [NodeID], registry: NodeRegistry) -> [NodeID: NodeID] {
        guard let path = path(entering: levelPath), let level = graph(at: path) else { return [:] }
        func identity(_ node: NodeID) -> NodeID { levelPath.isEmpty ? node : NodeID.scoped(levelPath + [node]) }
        var producers: [NodeID: NodeID] = [:]
        for node in level.nodes.values {
            producers[identity(node.id)] = node.id
            for inner in GroupScopes.inner(of: node, at: levelPath, definitions: definitions) {
                producers[inner] = node.id
            }
        }
        for placer in level.nodes.values where registry[placer.typeID]?.placesInstances == true {
            for tool in level.nodes.keys {
                producers[NodeID.instanceScoped([identity(placer.id), identity(tool)])] = placer.id
            }
        }
        return producers
    }
}
