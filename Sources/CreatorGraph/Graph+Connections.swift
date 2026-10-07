extension Graph {
    /// `nil` if `from` (an output) may be wired to `to` (an input), otherwise why not.
    public func connectionProblem(from: Endpoint, to: Endpoint, registry: NodeRegistry) -> ConnectionProblem? {
        guard let source = nodes[from.node], let target = nodes[to.node],
              let sourceDefinition = registry[source.typeID], let targetDefinition = registry[target.typeID] else {
            return .unknownNode
        }
        guard let output = sourceDefinition.outputs.first(where: { $0.name == from.socket }) else { return .unknownSocket(from.socket) }
        guard let input = targetDefinition.inputs.first(where: { $0.name == to.socket }) else { return .unknownSocket(to.socket) }
        guard from.node != to.node else { return .sameNode }
        guard input.type.accepts(output.type) else { return .typeMismatch(from: output.type, to: input.type) }
        guard !upstreamClosure(of: from.node).contains(to.node) else { return .wouldCreateCycle }
        return nil
    }
}
