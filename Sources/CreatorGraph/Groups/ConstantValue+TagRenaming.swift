import CreatorKernel

extension ConstantValue {
    /// This value with every tag of a remembered pick (`.edgePicks`, `.facePick`) that names a node in `names`
    /// renamed to the node it maps to, blend faces' source edges included; any other value, and tags naming other
    /// nodes, unchanged. Picks keep naming the faces they named when the identities those faces are made under change
    /// (groups spec §5): inside a group (`EvaluationScope.naming`) and across Group, Ungroup and Make Unique.
    func renamingTags(_ names: [NodeID: NodeID]) -> ConstantValue {
        guard !names.isEmpty else { return self }
        switch self {
        case .edgePicks(let picks):
            return .edgePicks(picks.map { pick in
                var renamed = pick
                renamed.key = Self.renaming(pick.key, names)
                return renamed
            })
        case .facePick(let pick):
            var renamed = pick
            renamed.tags = Self.renaming(pick.tags, names)
            return .facePick(renamed)
        default:
            return self
        }
    }

    private static func renaming(_ key: EdgeKey, _ names: [NodeID: NodeID]) -> EdgeKey {
        EdgeKey(renaming(key.first, names), renaming(key.second, names))
    }

    private static func renaming(_ tags: Set<TopoTag>, _ names: [NodeID: NodeID]) -> Set<TopoTag> {
        Set(tags.map { tag in
            var role = tag.role
            if case .blend(let edge) = tag.role { role = .blend(sourceEdge: renaming(edge, names)) }
            return TopoTag(node: names[tag.node] ?? tag.node, item: tag.item, role: role)
        })
    }
}
