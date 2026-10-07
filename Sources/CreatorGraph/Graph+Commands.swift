import CreatorKernel

extension Graph {
    /// Applies `command` and returns the command that undoes it. On error the graph is unchanged.
    @discardableResult
    public mutating func apply(_ command: GraphCommand, registry: NodeRegistry) throws(GraphError) -> GraphCommand {
        switch command {
        case .addNode(let node):
            guard nodes[node.id] == nil else { throw .duplicateNode(node.id) }
            nodes[node.id] = node
            return .removeNode(node.id)

        case .removeNode(let id):
            guard let node = nodes[id] else { throw .nodeNotFound(id) }
            let removed = links.filter { $0.from.node == id || $0.to.node == id }
            links.removeAll { $0.from.node == id || $0.to.node == id }
            nodes[id] = nil
            return .restoreNode(node, links: removed)

        case .restoreNode(let node, let restoredLinks):
            guard nodes[node.id] == nil else { throw .duplicateNode(node.id) }
            nodes[node.id] = node
            links += restoredLinks
            return .removeNode(node.id)

        case .connect(let link):
            if let problem = connectionProblem(from: link.from, to: link.to, registry: registry) {
                throw .invalidConnection(problem)
            }
            let replaced = incomingLink(to: link.to)
            links.removeAll { $0.to == link.to }
            links.append(link)
            if let replaced {
                return .batch([.disconnect(link), .connect(replaced)])
            }
            return .disconnect(link)

        case .disconnect(let link):
            guard links.contains(link) else { throw .linkNotFound }
            links.removeAll { $0 == link }
            return .connect(link)

        case .setInput(let id, let socket, let value):
            guard var node = nodes[id] else { throw .nodeNotFound(id) }
            if let value, !value.isFinite { throw .invalidValue("Enter a finite number.") }
            let old = node.inputValues[socket]
            node.inputValues[socket] = value
            nodes[id] = node
            return .setInput(id, socket, old)

        case .move(let id, let position):
            guard var node = nodes[id] else { throw .nodeNotFound(id) }
            let old = node.position
            node.position = position
            nodes[id] = node
            return .move(id, to: old)

        case .rename(let id, let name):
            guard var node = nodes[id] else { throw .nodeNotFound(id) }
            let old = node.name
            node.name = name
            nodes[id] = node
            return .rename(id, old)

        case .setOutput(let id, let isOutput):
            guard var node = nodes[id] else { throw .nodeNotFound(id) }
            let old = node.isOutput
            node.isOutput = isOutput
            nodes[id] = node
            return .setOutput(id, old)

        case .addParameter(let parameter):
            parameters.append(parameter)
            return .removeParameter(parameter.id)

        case .removeParameter(let id):
            guard let index = parameters.firstIndex(where: { $0.id == id }) else { throw .parameterNotFound(id) }
            let removed = parameters.remove(at: index)
            return .addParameter(removed)

        case .setParameter(let id, let value):
            guard let index = parameters.firstIndex(where: { $0.id == id }) else { throw .parameterNotFound(id) }
            guard value.isFinite else { throw .invalidValue("Enter a finite number.") }
            let old = parameters[index].value
            parameters[index].value = value
            return .setParameter(id, old)

        case .batch(let commands):
            let snapshot = self
            var inverses: [GraphCommand] = []
            do {
                for command in commands {
                    inverses.append(try apply(command, registry: registry))
                }
            } catch {
                self = snapshot
                throw error
            }
            return .batch(Array(inverses.reversed()))
        }
    }
}
