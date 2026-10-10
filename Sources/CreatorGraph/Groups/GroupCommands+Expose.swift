import CreatorKernel

/// Exposing a socket by wiring it to the "+" of Group Input or Group Output (groups spec §6). Each builds one command
/// that adds the socket and its wire together, to be performed while the definition's inside is shown, so the drop is
/// one undo step.
extension GroupCommands {
    /// Dropping a wire from `source`, an output of a node inside definition `id`, on Group Output's "+" (`boundary`):
    /// a new output named after the source socket (made unique), of its type and unit, wired from it.
    public static func exposeOutput(from source: Endpoint, on boundary: NodeID, in id: GroupID, of content: GraphContent,
                                    registry: NodeRegistry) throws(GraphError) -> GraphCommand {
        guard let definition = content.definitions[id] else { throw GroupRefusal.missing }
        guard let output = definition.outputNode, output.id == boundary else { throw GroupRefusal.boundaryCount }
        let sockets = registry.withGroups(content.definitions)
        guard let node = definition.graph.nodes[source.node],
              let spec = sockets.outputs(for: node).first(where: { $0.name == source.socket }) else { throw missingSocket }
        var interface = definition.interface
        let name = GroupNaming.uniqueSocketName(source.socket, among: interface.outputs.map(\.name))
        interface.outputs.append(SocketSpec(name, spec.type, unit: spec.unit))
        let wire = Link(from: source, to: Endpoint(node: output.id, socket: name))
        return .batch([.setInterface(id, interface), GraphCommand.connect(wire).at(.definition(id))])
    }

    /// Dragging from Group Input's "+" (`boundary`) onto `target`, an input of a node inside definition `id`: a new
    /// input named after the target socket (made unique) with its type, access, optional, unit, range and default, wired to
    /// it, so the part doesn't change when a literal is promoted to an input.
    public static func exposeInput(to target: Endpoint, from boundary: NodeID, in id: GroupID, of content: GraphContent,
                                   registry: NodeRegistry) throws(GraphError) -> GraphCommand {
        guard let definition = content.definitions[id] else { throw GroupRefusal.missing }
        guard let input = definition.inputNode, input.id == boundary else { throw GroupRefusal.boundaryCount }
        let sockets = registry.withGroups(content.definitions)
        guard let node = definition.graph.nodes[target.node],
              let spec = sockets.inputs(for: node).first(where: { $0.name == target.socket }) else { throw missingSocket }
        var interface = definition.interface
        let name = GroupNaming.uniqueSocketName(target.socket, among: interface.inputs.map(\.name))
        interface.inputs.append(SocketSpec(name, spec.type, access: spec.access, defaultValue: spec.defaultValue, unit: spec.unit,
                                          range: spec.range, optional: spec.isOptional))
        let wire = Link(from: Endpoint(node: input.id, socket: name), to: target)
        return .batch([.setInterface(id, interface), GraphCommand.connect(wire).at(.definition(id))])
    }
}
