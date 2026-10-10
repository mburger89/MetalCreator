extension Graph {
    /// `nil` if `from` (an output) may be wired to `to` (an input), otherwise why not. Sockets are
    /// `registry.outputs(for:)`/`inputs(for:)`, so a group node wires to its definition's sockets when the registry
    /// carries the document's groups.
    public func connectionProblem(from: Endpoint, to: Endpoint, registry: NodeRegistry) -> ConnectionProblem? {
        guard let source = nodes[from.node], let target = nodes[to.node],
              registry[source.typeID] != nil, registry[target.typeID] != nil else {
            return .unknownNode
        }
        guard let output = registry.outputs(for: source).first(where: { $0.name == from.socket }) else {
            return .unknownSocket(from.socket)
        }
        guard let input = registry.inputs(for: target).first(where: { $0.name == to.socket }) else {
            return .unknownSocket(to.socket)
        }
        guard from.node != to.node else { return .sameNode }
        guard input.type.accepts(output.type) else { return .typeMismatch(from: output.type, to: input.type) }
        guard !upstreamClosure(of: from.node).contains(to.node) else { return .wouldCreateCycle }
        return nil
    }
}
