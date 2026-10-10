import CreatorGeometry
import CreatorKernel

/// The group commands (groups spec §5), each built as one `GroupEdit` whose command `DocumentModel.perform` applies
/// as one undo step. Builders only read the document; `GraphContent.apply` checks the group rules again.
public enum GroupCommands {
    /// How far Group Input sits left of the grouped nodes, and Group Output right of them, inside a new definition.
    public static let boundaryMargin = 240.0

    /// Group (⌘G): moves `ids`, nodes of the graph at `path`, into a new definition named "Group" ("Group 2", …) and
    /// puts one group node of it at their top-left, selected. Links among them move with them; each distinct source
    /// outside that feeds them becomes one input (named after the first input it feeds, made unique) and each
    /// distinct source inside wired out becomes one output (named after it). Inputs and outputs are ordered by their
    /// nodes' places, top to bottom. The grouped nodes' faces are made under new identities (`NodeID.scoped`), so every
    /// pick outside the selection that names one is renamed to match; picks inside it name them as before. Refused for
    /// an empty selection, Group Input or Output, an Output node, a node outside the selection that both takes from
    /// it and feeds it (the group node would be wired in a cycle), or a boundary socket whose type can't be told.
    public static func group(_ ids: Set<NodeID>, in path: GraphPath, of content: GraphContent,
                             registry: NodeRegistry) throws(GraphError) -> GroupEdit {
        guard let graph = content.graph(at: path) else { throw GroupRefusal.missing }
        let sockets = registry.withGroups(content.definitions)
        let picked = try groupable(ids, in: graph, sockets: sockets)
        var builder = try GroupBuilder(picked, from: graph, content: content, sockets: sockets, registry: registry)
        for link in boundary(of: ids, in: graph, inbound: true) { try builder.wireIn(link) }
        for link in boundary(of: ids, in: graph, inbound: false) { try builder.wireOut(link) }

        let here: [GraphCommand] = ids.sorted().map { .removeNode($0) } + [.addNode(builder.groupNode)]
            + (builder.outside.isEmpty ? [] : [.restoreLinks(builder.outside)])
        let groupNode = builder.groupNode.id
        let picks = GroupScopes.renamingPicks(at: path, in: content, skipping: ids) { reached in
            guard let first = reached.first, ids.contains(first) else { return nil }
            return [groupNode] + reached
        }
        return GroupEdit(command: .batch([.addDefinition(builder.finished), GraphCommand.batch(here).at(path)] + picks),
                         selection: [groupNode])
    }

    /// The selected nodes, by ID, or why they can't be grouped.
    private static func groupable(_ ids: Set<NodeID>, in graph: Graph, sockets: NodeRegistry) throws(GraphError) -> [Node] {
        guard !ids.isEmpty else { throw .invalidValue("Select the nodes to group.") }
        var picked: [Node] = []
        for id in ids.sorted() {
            guard let node = graph.nodes[id] else { throw .nodeNotFound(id) }
            if GroupNodes.isBoundary(node) { throw .invalidValue("Group Input and Group Output can't go in a group.") }
            if node.isOutput || sockets[node.typeID]?.category == .output { throw GroupRefusal.outputInside }
            picked.append(node)
        }
        let after = graph.downstreamClosure(of: ids).subtracting(ids)
        let before = ids.reduce(into: Set<NodeID>()) { $0.formUnion(graph.upstreamClosure(of: $1)) }
        guard after.isDisjoint(with: before) else { throw GroupRefusal.wouldCycle }
        return picked
    }

    /// The links crossing into (`inbound`) or out of the selection, ordered by the place of the node inside it, top
    /// to bottom and then left to right, then by ID and socket, so the group's sockets follow the layout.
    private static func boundary(of ids: Set<NodeID>, in graph: Graph, inbound: Bool) -> [Link] {
        func order(_ link: Link) -> (Double, Double, String) {
            let end = inbound ? link.to : link.from
            let position = graph.nodes[end.node]?.position ?? .zero
            return (position.y, position.x, end.node.rawValue.uuidString + "." + end.socket.rawValue)
        }
        return graph.links.filter { link in
            let (inner, other) = inbound ? (link.to.node, link.from.node) : (link.from.node, link.to.node)
            return ids.contains(inner) && !ids.contains(other)
        }.sorted { order($0) < order($1) }
    }
}
