extension TopoTag {
    /// This tag as the copy numbered `item` of a placed tool carries it (patterns spec §6): the node `qualify`
    /// gives for this one, the copy's index as the item, the role unchanged. A blend role's source edge is
    /// qualified the same way, so a tool with a rounded tip names its blend faces by the copy too.
    public func qualified(item: Int, _ qualify: (NodeID) -> NodeID) -> TopoTag {
        TopoTag(node: qualify(node), item: item, role: role.qualified(item: item, qualify))
    }

    /// Every tag of a pick that names a placed copy: the tags of `tags` whose node is instance-qualified, and, inside
    /// a blend role, those of its source edge's faces.
    static func instanceTags(in tags: Set<TopoTag>) -> [TopoTag] {
        tags.flatMap { tag in
            var found = tag.node.isInstanceQualified ? [tag] : []
            found += instanceTags(in: tag.role.nestedTags)
            return found
        }
    }
}

extension TopoRole {
    func qualified(item: Int, _ qualify: (NodeID) -> NodeID) -> TopoRole {
        mappingNestedTags { $0.qualified(item: item, qualify) }
    }
}
