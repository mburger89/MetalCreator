import CreatorKernel
import Foundation

extension GraphContent {
    /// Applies `command` and returns the command that undoes it; on error nothing changes. Graph commands edit the
    /// top level, `.inDefinition` a definition's inside. Refused, with a plain message (groups spec §4, §5): a group
    /// containing itself, directly or through other groups; an Output node in a group; Group Input or Group Output
    /// outside a group, a second one, or deleting one; removing a definition in use; a bad name or socket list; and,
    /// once the whole command has applied, a socket removed from a definition or given another type while a wire is
    /// still on it, on a group node or inside on Group Input or Group Output.
    @discardableResult
    public mutating func apply(_ command: GraphCommand, registry: NodeRegistry) throws(GraphError) -> GraphCommand {
        let before = self
        let inverse = try applyCommand(command, registry: registry)
        do {
            try checkWiredSockets(changedBy: command, before: before)
        } catch {
            self = before
            throw error
        }
        return inverse
    }

    /// `apply` without the check across the whole command, so a batch can rename a socket and move its wires.
    private mutating func applyCommand(_ command: GraphCommand, registry: NodeRegistry) throws(GraphError) -> GraphCommand {
        switch command {
        case .batch(let commands):
            let snapshot = self
            var inverses: [GraphCommand] = []
            do {
                for command in commands {
                    inverses.append(try applyCommand(command, registry: registry))
                }
            } catch {
                self = snapshot
                throw error
            }
            return .batch(Array(inverses.reversed()))
        case .inDefinition, .addDefinition, .removeDefinition, .setInterface:
            return try applyGroupEdit(command, registry: registry)
        default:
            try check(command, in: .root, registry: registry)
            return try graph.apply(command, registry: registry.withGroups(definitions))
        }
    }

    /// The four group commands; `apply` routes them here.
    private mutating func applyGroupEdit(_ command: GraphCommand, registry: NodeRegistry) throws(GraphError) -> GraphCommand {
        switch command {
        case .inDefinition(let id, let inner):
            guard var definition = definitions[id] else { throw GroupRefusal.missing }
            try check(inner, in: .definition(id), registry: registry)
            let inverse = try definition.graph.apply(inner, registry: registry.withGroups(definitions))
            definitions[id] = definition
            return .inDefinition(id, inverse)
        case .addDefinition(let definition):
            try checkNew(definition, registry: registry)
            definitions[definition.id] = definition
            return .removeDefinition(definition.id)
        case .removeDefinition(let id):
            guard let definition = definitions[id] else { throw GroupRefusal.missing }
            guard GroupDependencies.instances(of: id, in: self).isEmpty else { throw GroupRefusal.inUse(definition.name) }
            definitions[id] = nil
            return .addDefinition(definition)
        case .setInterface(let id, let interface):
            guard var definition = definitions[id] else { throw GroupRefusal.missing }
            try checkInterface(interface, of: id)
            let old = definition.interface
            definition.interface = interface
            definitions[id] = definition
            return .setInterface(id, old)
        default:
            throw GroupRefusal.nested  // `apply` routes only the four group commands here.
        }
    }

    // MARK: - Rules

    /// Refuses a graph command that would break a group rule in the graph at `path`.
    private func check(_ command: GraphCommand, in path: GraphPath, registry: NodeRegistry) throws(GraphError) {
        switch command {
        case .batch(let commands):
            for command in commands { try check(command, in: path, registry: registry) }
        case .inDefinition, .addDefinition, .removeDefinition, .setInterface:
            throw GroupRefusal.nested
        case .addNode(let node), .restoreNode(let node, _):
            try checkPlacing(node, in: path, registry: registry)
        case .removeNode(let id):
            if let node = graph(at: path)?.nodes[id], GroupNodes.isBoundary(node) { throw GroupRefusal.boundaryDeleted }
        case .setOutput(_, true) where path != .root:
            throw GroupRefusal.outputInside
        case .setInput(let id, NodeSetting.group, let value):
            try checkRetargeting(id, to: value, in: path, registry: registry)
        default:
            break
        }
    }

    /// Refuses pointing a group node at a definition that's missing or would contain itself, and moving a Group
    /// Input or Output to another definition.
    private func checkRetargeting(_ id: NodeID, to value: ConstantValue?, in path: GraphPath,
                                  registry: NodeRegistry) throws(GraphError) {
        guard var node = graph(at: path)?.nodes[id] else { return }
        if GroupNodes.isBoundary(node) { throw GroupRefusal.boundaryMoved }
        node.inputValues[NodeSetting.group] = value
        if node.typeID == GroupNodes.groupTypeID { try checkPlacing(node, in: path, registry: registry) }
    }

    /// Refuses putting `node` in the graph at `path` when it breaks a group rule.
    private func checkPlacing(_ node: Node, in path: GraphPath, registry: NodeRegistry) throws(GraphError) {
        if GroupNodes.isBoundary(node) { throw path == .root ? GroupRefusal.boundaryOutside : GroupRefusal.boundaryCount }
        if path != .root, node.isOutput || registry[node.typeID]?.category == .output { throw GroupRefusal.outputInside }
        guard node.typeID == GroupNodes.groupTypeID else { return }
        guard let target = node.inputValues[NodeSetting.group]?.groupID, definitions[target] != nil else {
            throw GroupRefusal.missing
        }
        if GroupDependencies.wouldRecurse(placing: target, in: path, definitions: definitions) {
            throw GroupRefusal.containsItself
        }
    }

    /// Refuses a new definition that breaks a group rule: its ID or name taken, bad sockets, not exactly one Group
    /// Input and one Group Output (of this definition), an Output node inside, or a group inside that contains it.
    private func checkNew(_ definition: GroupDefinition, registry: NodeRegistry) throws(GraphError) {
        guard definitions[definition.id] == nil else { throw GroupRefusal.duplicateID }
        try checkInterface(definition.interface, of: definition.id)
        let boundary = definition.graph.nodes.values.filter(GroupNodes.isBoundary)
        guard boundary.count(where: { $0.typeID == GroupNodes.inputTypeID }) == 1,
              boundary.count(where: { $0.typeID == GroupNodes.outputTypeID }) == 1,
              boundary.allSatisfy({ $0.inputValues[NodeSetting.group]?.groupID == definition.id }) else {
            throw GroupRefusal.boundaryCount
        }
        var withNew = definitions
        withNew[definition.id] = definition
        for node in definition.graph.nodes.values where !GroupNodes.isBoundary(node) {
            if node.isOutput || registry[node.typeID]?.category == .output { throw GroupRefusal.outputInside }
            guard node.typeID == GroupNodes.groupTypeID else { continue }
            guard let target = node.inputValues[NodeSetting.group]?.groupID, withNew[target] != nil else {
                throw GroupRefusal.missing
            }
            if GroupDependencies.wouldRecurse(placing: target, in: .definition(definition.id), definitions: withNew) {
                throw GroupRefusal.containsItself
            }
        }
    }

    /// Refuses the sockets `command` removed from a definition, or gave another type, that still have a wire: on any
    /// group node of it, or inside on Group Input (an input) or Group Output (an output). `before` is the content the
    /// command applied to.
    private func checkWiredSockets(changedBy command: GraphCommand, before: GraphContent) throws(GraphError) {
        for id in command.interfaceEdits {
            guard let old = before.definitions[id], let definition = definitions[id] else { continue }
            for side in [GroupSocketSide.input, .output] {
                let kept = side == .input ? definition.inputs : definition.outputs
                for socket in side == .input ? old.inputs : old.outputs
                where !kept.contains(where: { $0.name == socket.name && $0.type == socket.type }) {
                    if let node = nodeWiring(socket.name, side: side, of: definition) {
                        throw .invalidValue("“\(socket.name)” is wired on “\(node.name)”. Unwire it first.")
                    }
                }
            }
        }
    }

    /// The first node with a wire on socket `name` of definition `definition`: a group node of it, or Group Input or
    /// Group Output inside it.
    private func nodeWiring(_ name: SocketName, side: GroupSocketSide, of definition: GroupDefinition) -> Node? {
        for instance in GroupDependencies.instances(of: definition.id, in: self) {
            let socket = Endpoint(node: instance.node.id, socket: name)
            if graph(at: instance.path)?.links.contains(where: { side == .input ? $0.to == socket : $0.from == socket }) == true {
                return instance.node
            }
        }
        guard let boundary = side == .input ? definition.inputNode : definition.outputNode else { return nil }
        let socket = Endpoint(node: boundary.id, socket: name)
        return definition.graph.links.contains { side == .input ? $0.from == socket : $0.to == socket } ? boundary : nil
    }

    /// Refuses an empty or taken name, and a side whose socket names are empty, reserved or repeated.
    private func checkInterface(_ interface: GroupInterface, of id: GroupID) throws(GraphError) {
        guard !interface.name.trimmingCharacters(in: .whitespaces).isEmpty else { throw GroupRefusal.emptyName }
        if definitions.values.contains(where: { $0.id != id && $0.name == interface.name }) {
            throw GroupRefusal.nameTaken(interface.name)
        }
        for sockets in [interface.inputs, interface.outputs] {
            if let problem = GroupNaming.problem(with: sockets) { throw .invalidValue(problem) }
        }
    }
}
