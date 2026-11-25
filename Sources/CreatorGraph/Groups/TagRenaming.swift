import CreatorKernel

/// The tag renaming every pick shares (`ConstantValue.renamingTags`, `DrawingDocument.renamingTags`): tags naming a
/// node in `names` name the node it maps to, blend faces' source edges included.
enum TagRenaming {
    static func renaming(_ key: EdgeKey, _ names: [NodeID: NodeID]) -> EdgeKey {
        EdgeKey(renaming(key.first, names), renaming(key.second, names))
    }

    static func renaming(_ tags: Set<TopoTag>, _ names: [NodeID: NodeID]) -> Set<TopoTag> {
        Set(tags.map { tag in
            let role = tag.role.mappingNestedTags { renaming([$0], names).first ?? $0 }
            return TopoTag(node: names[tag.node] ?? tag.node, item: tag.item, role: role)
        })
    }

    static func renaming(_ pick: EdgePick, _ names: [NodeID: NodeID]) -> EdgePick {
        var renamed = pick
        renamed.key = renaming(pick.key, names)
        return renamed
    }

    static func renaming(_ pick: FacePick, _ names: [NodeID: NodeID]) -> FacePick {
        var renamed = pick
        renamed.tags = renaming(pick.tags, names)
        return renamed
    }
}
