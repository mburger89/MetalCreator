import CreatorGraph

/// One category of the node library: its title and its types (spec §6.6 colours its header).
public struct LibrarySection: Equatable, Sendable, Identifiable {
    public var category: NodeCategory
    public var entries: [PaletteEntry]

    public var id: NodeCategory { category }

    public var title: String { Self.title(for: category) }

    /// "Value", "Profile", "Solid", "Selection", "Feature", "Lists & Trees", "Output".
    public static func title(for category: NodeCategory) -> String { category.title }

    /// `entries` grouped by category, in `NodeCategory.allCases` order, keeping their order within each group;
    /// a category with no entries is left out.
    public static func grouping(_ entries: [PaletteEntry]) -> [LibrarySection] {
        NodeCategory.allCases.compactMap { category in
            let members = entries.filter { $0.category == category }
            return members.isEmpty ? nil : LibrarySection(category: category, entries: members)
        }
    }
}
