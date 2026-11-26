import CreatorKernel

extension ConstantValue {
    /// This value with every tag of a remembered pick (`.edgePicks`, `.facePick`, `.regionPicks`) that names a node in `names`
    /// renamed to the node it maps to, blend faces' source edges included; any other value, and tags naming other
    /// nodes, unchanged. Picks keep naming the faces they named when the identities those faces are made under change
    /// (groups spec §5): inside a group (`EvaluationScope.naming`) and across Group, Ungroup and Make Unique.
    func renamingTags(_ names: [NodeID: NodeID]) -> ConstantValue {
        guard !names.isEmpty else { return self }
        switch self {
        case .edgePicks(let picks):
            return .edgePicks(picks.map { TagRenaming.renaming($0, names) })
        case .facePick(let pick):
            return .facePick(TagRenaming.renaming(pick, names))
        case .regionPicks(let picks):
            return .regionPicks(picks.map { region in
                var renamed = region
                renamed.pick.tags = TagRenaming.renaming(region.pick.tags, names)
                return renamed
            })
        default:
            return self
        }
    }
}
