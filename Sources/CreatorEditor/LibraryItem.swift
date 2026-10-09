import CreatorGraph

/// One row of the node library's list: a category's header, or one of its types. The library is one flat,
/// uniformly tall list so MetalUI's `List` builds only the rows in view (docs/metalui-gaps.md PERF-b).
public struct LibraryItem: Equatable, Sendable, Identifiable {
    public var category: NodeCategory
    /// The type, or `nil` for the category's header.
    public var entry: PaletteEntry?

    /// The header's "header.<category>", or the type's ID.
    public var id: String { entry?.typeID ?? "header.\(category.rawValue)" }

    /// The rows of `sections`: each category's header, then its types.
    public static func rows(_ sections: [LibrarySection]) -> [LibraryItem] {
        sections.flatMap { section in
            [LibraryItem(category: section.category, entry: nil)]
                + section.entries.map { LibraryItem(category: section.category, entry: $0) }
        }
    }
}
