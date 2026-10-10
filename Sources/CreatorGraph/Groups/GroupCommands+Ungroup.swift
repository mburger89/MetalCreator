import CreatorKernel

extension GroupCommands {
    /// Ungroup (⇧⌘G): splices group node `id`, in the graph at `path`, back into that graph and selects what it
    /// spliced (groups spec §5). Its definition's nodes come back with fresh IDs, placed relative to the group node.
    /// Whatever fed an input of the group node now feeds what Group Input fed with it; an unwired input's typed value
    /// (or its default) is written onto those inner inputs instead. What took an output of the group node now takes
    /// what fed Group Output, and where Group Input fed Group Output straight through, what fed that input (or its
    /// value). The definition is removed with its last group node. Picks on the spliced nodes' faces, outside them or
    /// inside, are renamed to the nodes' new IDs, so they keep naming the same faces.
    public static func ungroup(_ id: NodeID, in path: GraphPath, of content: GraphContent,
                               registry: NodeRegistry) throws(GraphError) -> GroupEdit {
        let (graph, instance, definition) = try groupNode(id, in: path, of: content, registry: registry, action: "ungroup")
        guard let input = definition.inputNode, let output = definition.outputNode else { throw GroupRefusal.boundaryCount }
        var splice = GroupSplice(definition: definition, at: instance.position, definitions: content.definitions)
        for spec in definition.inputs {
            let external = graph.incomingLink(to: Endpoint(node: id, socket: spec.name))?.from
            let value = instance.inputValues[spec.name] ?? spec.defaultValue
            for link in definition.graph.links where link.from == Endpoint(node: input.id, socket: spec.name) {
                splice.feed(link.to, from: external, value: value)
            }
        }
        var settings: [GraphCommand] = []
        for spec in definition.outputs {
            guard let source = definition.graph.incomingLink(to: Endpoint(node: output.id, socket: spec.name))?.from else { continue }
            let throughFrom = source.node == input.id
                ? graph.incomingLink(to: Endpoint(node: id, socket: source.socket))?.from : splice.endpoint(source)
            let throughValue = source.node == input.id
                ? instance.inputValues[source.socket] ?? definition.inputs.first { $0.name == source.socket }?.defaultValue : nil
            for link in graph.links where link.from == Endpoint(node: id, socket: spec.name) {
                if let throughFrom {
                    splice.links.append(Link(from: throughFrom, to: link.to))
                } else if let throughValue {
                    settings.append(.setInput(link.to.node, link.to.socket, throughValue))
                }
            }
        }
        let here: [GraphCommand] = [.removeNode(id)] + splice.nodes.values.sorted { $0.id < $1.id }.map { .addNode($0) }
            + (splice.links.isEmpty ? [] : [.restoreLinks(splice.links)]) + settings
        let lastOne = GroupDependencies.instances(of: definition.id, in: content).allSatisfy { $0.path == path && $0.node.id == id }
        let fresh = splice.fresh
        let picks = GroupScopes.renamingPicks(at: path, in: content, skipping: [id]) { reached in
            guard reached.count > 1, reached.first == id, let copy = fresh[reached[1]] else { return nil }
            return [copy] + reached.dropFirst(2)
        }
        return GroupEdit(command: .batch([GraphCommand.batch(here).at(path)] + picks
                                         + (lastOne ? [.removeDefinition(definition.id)] : [])),
                         selection: Set(splice.nodes.keys))
    }

    /// The graph at `path`, group node `id` in it and its definition, or a refusal naming `action`.
    static func groupNode(_ id: NodeID, in path: GraphPath, of content: GraphContent, registry: NodeRegistry,
                          action: String) throws(GraphError) -> (Graph, Node, GroupDefinition) {
        guard let graph = content.graph(at: path) else { throw GroupRefusal.missing }
        guard let node = graph.nodes[id] else { throw .nodeNotFound(id) }
        guard node.typeID == GroupNodes.groupTypeID else { throw .invalidValue("Select one group node to \(action).") }
        guard let definition = registry.withGroups(content.definitions).group(of: node) else { throw GroupRefusal.missing }
        return (graph, node, definition)
    }
}
