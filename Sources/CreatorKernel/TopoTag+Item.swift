extension TopoTag {
    /// This tag with `item` as its item, a blend role's source edge too: a placed copy's faces are first named by the
    /// copy's flat index (`Kernel.place`) and then by its path (`Topology.withInstanceItem(_:)`).
    func withItem(_ item: Int) -> TopoTag {
        TopoTag(node: node, item: item, role: role.withItem(item))
    }
}

extension TopoRole {
    func withItem(_ item: Int) -> TopoRole {
        guard case .blend(let edge) = self else { return self }
        return .blend(sourceEdge: EdgeKey(Set(edge.first.map { $0.withItem(item) }), Set(edge.second.map { $0.withItem(item) })))
    }
}
