import CreatorGraph
import CreatorKernel
import CreatorNodes

/// The nodes that belong to one feature alone (DIM-3 decision 2): selecting a feature shows its dimensions and those of
/// the private nodes that feed it, such as the sketch behind an Extrude.
enum FeatureChain {
    /// `node` and every upstream node all of whose consumers are in the chain, through non-body links only (a body link is a
    /// wire of type `.solid`, `.implicit` or `.mesh`). The walk stops at Graph Parameter and Group Input nodes and at a node
    /// flagged `isOutput`, which counts as having another consumer. `registry` gives the sockets' types; a socket it doesn't
    /// know (a group node's, in a registry without the document's groups) counts as a body wire.
    static func nodes(of node: NodeID, in graph: Graph, registry: NodeRegistry = BuiltInNodes.registry) -> Set<NodeID> {
        guard graph.nodes[node] != nil else { return [] }
        var chain: Set<NodeID> = [node]
        var grew = true
        while grew {
            grew = false
            for link in graph.links where chain.contains(link.to.node) && !chain.contains(link.from.node) {
                guard let source = graph.nodes[link.from.node], canJoin(source), !isBodyWire(link, in: graph, registry: registry)
                else { continue }
                let consumers = graph.links.filter { $0.from.node == source.id }
                if consumers.allSatisfy({ chain.contains($0.to.node) }) {
                    chain.insert(source.id)
                    grew = true
                }
            }
        }
        return chain
    }

    private static func canJoin(_ node: Node) -> Bool {
        !node.isOutput && node.typeID != GraphParameterNode.typeID && node.typeID != GroupNodes.inputTypeID
    }

    private static func isBodyWire(_ link: Link, in graph: Graph, registry: NodeRegistry) -> Bool {
        guard let source = graph.nodes[link.from.node],
              let output = registry.outputs(for: source).first(where: { $0.name == link.from.socket }) else { return true }
        switch output.type {
        case .solid, .implicit, .mesh: return true
        default: return false
        }
    }
}
