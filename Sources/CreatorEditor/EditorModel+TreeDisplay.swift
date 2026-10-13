import CreatorGraph
import CreatorKernel

extension EditorModel {
    /// The tree a socket's output holds in the graph shown, or `nil` when it holds one item, a flat list or nothing.
    func tree(on endpoint: Endpoint) -> DataTree? {
        if case .tree(let tree)? = result(of: endpoint.node)?.outputs?[endpoint.socket] { tree } else { nil }
    }

    /// The tooltip of each socket of `node` that carries a data tree, keyed like `NodeRowModel.id` ("in.tree",
    /// "out.values"): "Tree 3 × 8". An input shows the tree wired into it. A socket that carries a field shows its recipe, cut
    /// to 80 characters ("3 fields" for a list of them), on the output and on the input it is wired into (fields spec §2.1).
    /// Sockets carrying one item or a flat list of anything else have no entry, and neither does a node with no result yet.
    public func socketHelp(of node: NodeID) -> [String: String] {
        var help: [String: String] = [:]
        for link in graph.links where link.to.node == node {
            if let tree = tree(on: link.from) {
                help["in.\(link.to.socket.rawValue)"] = "Tree \(tree.shapeText)"
            } else if let recipe = result(of: link.from.node)?.outputs?[link.from.socket]?.fieldSummary(limit: Self.tooltipLimit) {
                help["in.\(link.to.socket.rawValue)"] = recipe
            }
        }
        for (socket, value) in result(of: node)?.outputs ?? [:] {
            if case .tree(let tree) = value {
                help["out.\(socket.rawValue)"] = "Tree \(tree.shapeText)"
            } else if let recipe = value.fieldSummary(limit: Self.tooltipLimit) {
                help["out.\(socket.rawValue)"] = recipe
            }
        }
        return help
    }

    /// The longest field recipe a tooltip shows (fields spec §2.1).
    static let tooltipLimit = 80

    /// Opens or closes the path list of the tree on a socket (`TreeShapeRow.key`). View state: never undone or saved.
    public func toggleShapeList(_ key: String) {
        if expandedShapeLists.contains(key) {
            expandedShapeLists.remove(key)
        } else {
            expandedShapeLists.insert(key)
        }
    }
}
