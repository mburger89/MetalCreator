import CreatorGraph

/// A run of a category's types under one quiet heading (`title`), or under none.
public struct LibrarySubgroup: Equatable, Sendable {
    /// The heading, or `nil` for a run shown without one.
    public var title: String?
    public var entries: [PaletteEntry]

    public init(title: String?, entries: [PaletteEntry]) {
        self.title = title
        self.entries = entries
    }
}

/// One category of the node library: its title and its types (spec §6.6 colours its header).
public struct LibrarySection: Equatable, Sendable, Identifiable {
    public var category: NodeCategory
    /// The types, in the order the library lists them (the sub-groups' entries in turn when grouped).
    public var entries: [PaletteEntry]
    /// The same types in runs: one headed run per sub-group that has types, then the types with no sub-group; a single
    /// headless run when alphabetical or when the category has no sub-groups.
    public var subgroups: [LibrarySubgroup]

    public var id: NodeCategory { category }

    public var title: String { Self.title(for: category) }

    public init(category: NodeCategory, entries: [PaletteEntry], subgroups: [LibrarySubgroup]? = nil) {
        self.category = category
        self.entries = entries
        self.subgroups = subgroups ?? [LibrarySubgroup(title: nil, entries: entries)]
    }

    /// "Value", "Profile", "Solid", "Selection", "Feature", "Patterns", "Lists & Trees", "Fields", "Output".
    public static func title(for category: NodeCategory) -> String { category.title }

    /// `entries` grouped by category, in `NodeCategory.allCases` order, keeping their order within each group;
    /// a category with no entries is left out. Grouped, a category with sub-groups lists each under its heading in
    /// `NodeCategory.librarySubgroups` order (a heading with no types is left out), keeping the entries' order within it, and
    /// the types with no sub-group after them under no heading; alphabetical (or a category without sub-groups) it is one run.
    public static func grouping(_ entries: [PaletteEntry], sort: LibrarySort = .alphabetical) -> [LibrarySection] {
        NodeCategory.allCases.compactMap { category in
            let members = entries.filter { $0.category == category }
            guard !members.isEmpty else { return nil }
            let names = category.librarySubgroups
            guard sort == .grouped, !names.isEmpty else { return LibrarySection(category: category, entries: members) }
            var runs = names.compactMap { name -> LibrarySubgroup? in
                let run = members.filter { $0.subgroup == name }
                return run.isEmpty ? nil : LibrarySubgroup(title: name, entries: run)
            }
            let rest = members.filter { $0.subgroup.map { !names.contains($0) } ?? true }
            if !rest.isEmpty { runs.append(LibrarySubgroup(title: nil, entries: rest)) }
            return LibrarySection(category: category, entries: runs.flatMap(\.entries), subgroups: runs)
        }
    }
}
