import CreatorKernel

extension GroupCommands {
    /// Make Unique: copies group node `id`'s definition as "Name 2" (the next free number), with fresh IDs for every
    /// node inside, and points this group node, renamed to match, at the copy (groups spec §5). Picks on this group
    /// node's faces, and the copy's own picks, are renamed to the new IDs, so they keep naming the same faces.
    public static func makeUnique(_ id: NodeID, in path: GraphPath, of content: GraphContent,
                                  registry: NodeRegistry) throws(GraphError) -> GroupEdit {
        let (_, _, definition) = try groupNode(id, in: path, of: content, registry: registry, action: "make unique")
        let copyID = GroupID()
        var copy = GroupDefinition(id: copyID, name: GroupNaming.uniqueDefinitionName(definition.name, among: content.definitions),
                                   accent: definition.accent, inputs: definition.inputs, outputs: definition.outputs)
        let fresh = Dictionary(uniqueKeysWithValues: definition.graph.nodes.keys.map { ($0, NodeID()) })
        let names = GroupScopes.names(in: definition.graph, definitions: content.definitions) { path in
            path.first.flatMap { fresh[$0] }.map { [$0] + path.dropFirst() }
        }
        for node in definition.graph.nodes.values {
            var inner = node.renamingTags(names)
            inner.id = fresh[node.id] ?? NodeID()
            if GroupNodes.isBoundary(inner) { inner.inputValues[NodeSetting.group] = .group(copyID) }
            copy.graph.nodes[inner.id] = inner
        }
        copy.graph.links = definition.graph.links.compactMap { link in
            guard let from = fresh[link.from.node], let to = fresh[link.to.node] else { return nil }
            return Link(from: Endpoint(node: from, socket: link.from.socket), to: Endpoint(node: to, socket: link.to.socket))
        }
        copy.graph.sortLinks()
        let here = GraphCommand.batch([.setInput(id, NodeSetting.group, .group(copyID)), .rename(id, copy.name)])
        let picks = GroupScopes.renamingPicks(at: path, in: content) { reached in
            guard reached.count > 1, reached.first == id, let copy = fresh[reached[1]] else { return nil }
            return [id, copy] + reached.dropFirst(2)
        }
        return GroupEdit(command: .batch([.addDefinition(copy), here.at(path)] + picks), selection: [id])
    }
}
