import CreatorGraph

/// One node type offered by the add-node palette.
public struct PaletteEntry: Equatable, Sendable, Identifiable {
    public var typeID: String
    public var displayName: String
    public var category: NodeCategory
    /// A group definition's accent, which colours its dot in place of the category's.
    public var accent: AccentRole?

    public var id: String { typeID }

    public init(typeID: String, displayName: String, category: NodeCategory, accent: AccentRole? = nil) {
        self.typeID = typeID
        self.displayName = displayName
        self.category = category
        self.accent = accent
    }
}
