import CreatorKernel

/// Definition edits (groups spec §5): rename, accent, sockets, delete. Each builds one command; `GraphContent.apply`
/// refuses an empty or taken name and repeated or reserved socket names.
extension GroupCommands {
    static let missingSocket = GraphError.invalidValue("That socket no longer exists.")

    /// Renames definition `id`, and each of its group nodes still named after it.
    public static func rename(_ id: GroupID, to name: String, in content: GraphContent) throws(GraphError) -> GraphCommand {
        guard let definition = content.definitions[id] else { throw GroupRefusal.missing }
        var interface = definition.interface
        interface.name = name
        let renames = GroupDependencies.instances(of: id, in: content).filter { $0.node.name == definition.name }
            .map { GraphCommand.rename($0.node.id, name).at($0.path) }
        return .batch([.setInterface(id, interface)] + renames)
    }

    public static func setAccent(_ id: GroupID, _ accent: AccentRole, in content: GraphContent) throws(GraphError) -> GraphCommand {
        guard let definition = content.definitions[id] else { throw GroupRefusal.missing }
        var interface = definition.interface
        interface.accent = accent
        return .setInterface(id, interface)
    }

    /// Adds a socket named `name` (made unique on its side) of `type`; returns the command and the name it got.
    public static func addSocket(_ id: GroupID, side: GroupSocketSide, name: SocketName, type: SocketType,
                                 in content: GraphContent) throws(GraphError) -> (command: GraphCommand, name: SocketName) {
        guard let definition = content.definitions[id] else { throw GroupRefusal.missing }
        var interface = definition.interface
        let unique = GroupNaming.uniqueSocketName(name, among: (side == .input ? interface.inputs : interface.outputs).map(\.name))
        if side == .input { interface.inputs.append(SocketSpec(unique, type)) } else { interface.outputs.append(SocketSpec(unique, type)) }
        return (.setInterface(id, interface), unique)
    }

    /// Moves the socket at `from` to `to` on its side; wires follow it by name.
    public static func moveSocket(_ id: GroupID, side: GroupSocketSide, from: Int, to: Int,
                                  in content: GraphContent) throws(GraphError) -> GraphCommand {
        guard let definition = content.definitions[id] else { throw GroupRefusal.missing }
        var interface = definition.interface
        var sockets = side == .input ? interface.inputs : interface.outputs
        guard sockets.indices.contains(from), sockets.indices.contains(to) else { throw missingSocket }
        sockets.insert(sockets.remove(at: from), at: to)
        if side == .input { interface.inputs = sockets } else { interface.outputs = sockets }
        return .setInterface(id, interface)
    }

    /// Renames socket `old` to `new` everywhere: on the definition, on Group Input's or Group Output's wires inside,
    /// and on every group node's wires and typed value.
    public static func renameSocket(_ id: GroupID, side: GroupSocketSide, from old: SocketName, to new: SocketName,
                                    in content: GraphContent) throws(GraphError) -> GraphCommand {
        guard let definition = content.definitions[id] else { throw GroupRefusal.missing }
        var interface = definition.interface
        let sockets = side == .input ? interface.inputs : interface.outputs
        guard let index = sockets.firstIndex(where: { $0.name == old }) else { throw missingSocket }
        guard new != old else { return .batch([]) }
        if side == .input { interface.inputs[index].name = new } else { interface.outputs[index].name = new }
        var commands: [GraphCommand] = [.setInterface(id, interface)]
        let boundary = side == .input ? definition.inputNode : definition.outputNode
        if let boundary {
            commands.append(rewire(definition.graph, node: boundary.id, from: old, to: new, outgoing: side == .input)
                .at(.definition(id)))
        }
        for instance in GroupDependencies.instances(of: id, in: content) {
            guard let graph = content.graph(at: instance.path) else { continue }
            var here = [rewire(graph, node: instance.node.id, from: old, to: new, outgoing: side == .output)]
            if side == .input, let value = instance.node.inputValues[old] {
                here += [.setInput(instance.node.id, old, nil), .setInput(instance.node.id, new, value)]
            }
            commands.append(GraphCommand.batch(here).at(instance.path))
        }
        return .batch(commands)
    }

    /// Removes socket `name`, its wires inside and its typed values on group nodes. Refused while a group node has it
    /// wired, naming that node.
    public static func removeSocket(_ id: GroupID, side: GroupSocketSide, name: SocketName,
                                    in content: GraphContent) throws(GraphError) -> GraphCommand {
        guard let definition = content.definitions[id] else { throw GroupRefusal.missing }
        var interface = definition.interface
        guard (side == .input ? interface.inputs : interface.outputs).contains(where: { $0.name == name }) else {
            throw missingSocket
        }
        let instances = GroupDependencies.instances(of: id, in: content)
        for instance in instances {
            let socket = Endpoint(node: instance.node.id, socket: name)
            let links = content.graph(at: instance.path)?.links ?? []
            if links.contains(where: { side == .input ? $0.to == socket : $0.from == socket }) {
                throw .invalidValue("“\(name)” is wired on “\(instance.node.name)”. Unwire it first.")
            }
        }
        if side == .input { interface.inputs.removeAll { $0.name == name } } else { interface.outputs.removeAll { $0.name == name } }
        var commands: [GraphCommand] = [.setInterface(id, interface)]
        if let boundary = side == .input ? definition.inputNode : definition.outputNode {
            let socket = Endpoint(node: boundary.id, socket: name)
            let wires = definition.graph.links.filter { side == .input ? $0.from == socket : $0.to == socket }
            commands += wires.map { GraphCommand.disconnect($0).at(.definition(id)) }
        }
        for instance in instances where side == .input && instance.node.inputValues[name] != nil {
            commands.append(GraphCommand.setInput(instance.node.id, name, nil).at(instance.path))
        }
        return .batch(commands)
    }

    /// Delete: removes definition `id`, refused while a group node uses it.
    public static func deleteDefinition(_ id: GroupID, in content: GraphContent) throws(GraphError) -> GraphCommand {
        guard let definition = content.definitions[id] else { throw GroupRefusal.missing }
        guard GroupDependencies.instances(of: id, in: content).isEmpty else { throw GroupRefusal.inUse(definition.name) }
        return .removeDefinition(id)
    }

    /// Moves the wires on socket `old` of `node` to socket `new`: those leaving it (`outgoing`) or the one entering.
    private static func rewire(_ graph: Graph, node: NodeID, from old: SocketName, to new: SocketName,
                               outgoing: Bool) -> GraphCommand {
        let socket = Endpoint(node: node, socket: old), renamed = Endpoint(node: node, socket: new)
        let moving = graph.links.filter { outgoing ? $0.from == socket : $0.to == socket }
        guard !moving.isEmpty else { return .batch([]) }
        let moved = moving.map { outgoing ? Link(from: renamed, to: $0.to) : Link(from: $0.from, to: renamed) }
        return .batch(moving.map { .disconnect($0) } + [.restoreLinks(moved)])
    }
}
