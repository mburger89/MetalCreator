import CreatorGeometry
import CreatorKernel

/// A definition's nodes on their way out of it (Ungroup): copies with fresh IDs, placed relative to the group node,
/// and the links among them, to which Ungroup adds the ones across the old boundary. The copies' picks name the
/// copies, as the originals' named the originals.
struct GroupSplice {
    private(set) var nodes: [NodeID: Node] = [:]
    var links: [Link] = []
    /// Each inner node's copy, by the inner node's ID.
    private(set) var fresh: [NodeID: NodeID] = [:]

    init(definition: GroupDefinition, at origin: Vector2, definitions: [GroupID: GroupDefinition],
         registry: NodeRegistry) {
        for node in definition.graph.nodes.values where !GroupNodes.isBoundary(node) {
            fresh[node.id] = NodeID()
        }
        let names = GroupScopes.names(in: definition.graph, definitions: definitions, registry: registry) { [fresh] path in
            path.first.flatMap { fresh[$0] }.map { [$0] + path.dropFirst() }
        }
        for node in definition.graph.nodes.values {
            guard let id = fresh[node.id] else { continue }
            var copy = node.renamingTags(names)
            copy.id = id
            copy.position = node.position + origin
            nodes[id] = copy
        }
        links = definition.graph.links.compactMap { link in
            guard let from = endpoint(link.from), let to = endpoint(link.to) else { return nil }
            return Link(from: from, to: to)
        }
    }

    /// `endpoint` of an inner node, on its spliced copy; `nil` for Group Input and Group Output.
    func endpoint(_ endpoint: Endpoint) -> Endpoint? {
        fresh[endpoint.node].map { Endpoint(node: $0, socket: endpoint.socket) }
    }

    /// Feeds inner input `target` from `source` outside, or else writes `value` onto it.
    mutating func feed(_ target: Endpoint, from source: Endpoint?, value: ConstantValue?) {
        guard let spliced = endpoint(target) else { return }
        if let source {
            links.append(Link(from: source, to: spliced))
        } else if let value {
            nodes[spliced.node]?.inputValues[spliced.socket] = value
        }
    }
}
