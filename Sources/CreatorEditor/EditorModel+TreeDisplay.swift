import CreatorGraph
import CreatorKernel

extension EditorModel {
    /// The tree a socket's output holds in the graph shown, or `nil` when it holds one item, a flat list or nothing.
    func tree(on endpoint: Endpoint) -> DataTree? {
        if case .tree(let tree)? = result(of: endpoint.node)?.outputs?[endpoint.socket] { tree } else { nil }
    }

    /// The tooltip of each socket of `node` that carries a data tree, keyed like `NodeRowModel.id` ("in.tree",
    /// "out.values"): "Tree 3 × 8". An input shows the tree wired into it. Sockets carrying one item or a flat list have
    /// no entry, and neither does a node with no result yet.
    public func socketHelp(of node: NodeID) -> [String: String] {
        var help: [String: String] = [:]
        for link in graph.links where link.to.node == node {
            if let tree = tree(on: link.from) { help["in.\(link.to.socket.rawValue)"] = "Tree \(tree.shapeText)" }
        }
        for (socket, value) in result(of: node)?.outputs ?? [:] {
            if case .tree(let tree) = value { help["out.\(socket.rawValue)"] = "Tree \(tree.shapeText)" }
        }
        return help
    }

    /// Opens or closes the path list of the tree on a socket (`TreeShapeRow.key`). View state: never undone or saved.
    public func toggleShapeList(_ key: String) {
        if expandedShapeLists.contains(key) {
            expandedShapeLists.remove(key)
        } else {
            expandedShapeLists.insert(key)
        }
    }
}
