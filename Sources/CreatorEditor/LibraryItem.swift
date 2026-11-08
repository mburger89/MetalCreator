import CreatorGraph

/// One row of the node library's list: a category's header, or one of its types. The library is one flat,
/// uniformly tall list so MetalUI's `List` builds only the rows in view (docs/metalui-gaps.md PERF-b).
public struct LibraryItem: Equatable, Sendable, Identifiable {
    public var category: NodeCategory
    /// The type, or `nil` for a header.
    public var entry: PaletteEntry?
    /// A group definition in the "Groups" section (groups spec §6), or `nil`.
    public var group: GroupLibraryEntry?
    /// The "Groups" section's header.
    public var isGroupsHeader = false
    /// A sub-group's heading, or `nil`.
    public var subgroupTitle: String?

    /// The header's "header.<category>" ("header.groups"), the type's ID, or the group's key.
    public var id: String {
        if let group { return group.key }
        if isGroupsHeader { return "header.groups" }
        if let subgroupTitle { return "subheader.\(category.rawValue).\(subgroupTitle)" }
        return entry?.typeID ?? "header.\(category.rawValue)"
    }

    public init(category: NodeCategory, entry: PaletteEntry?, group: GroupLibraryEntry? = nil, isGroupsHeader: Bool = false,
                subgroupTitle: String? = nil) {
        self.subgroupTitle = subgroupTitle
        self.category = category
        self.entry = entry
        self.group = group
        self.isGroupsHeader = isGroupsHeader
    }

    /// The rows of `sections`: each category's header, then its types (under a sub-group's heading, when it has one); then, when there are `groups`, the "Groups"
    /// header and one row each.
    public static func rows(_ sections: [LibrarySection], groups: [GroupLibraryEntry] = []) -> [LibraryItem] {
        let nodes = sections.flatMap { section in
            [LibraryItem(category: section.category, entry: nil)]
                + section.subgroups.flatMap { run in
                    (run.title.map { [LibraryItem(category: section.category, entry: nil, subgroupTitle: $0)] } ?? [])
                        + run.entries.map { LibraryItem(category: section.category, entry: $0) }
                }
        }
        guard !groups.isEmpty else { return nodes }
        return nodes + [LibraryItem(category: .feature, entry: nil, isGroupsHeader: true)]
            + groups.map { LibraryItem(category: .feature, entry: nil, group: $0) }
    }
}
