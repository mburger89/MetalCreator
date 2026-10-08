import CreatorGraph

/// One node type offered by the add-node palette.
public struct PaletteEntry: Equatable, Sendable, Identifiable {
    public var typeID: String
    public var displayName: String
    public var category: NodeCategory

    public var id: String { typeID }
}
