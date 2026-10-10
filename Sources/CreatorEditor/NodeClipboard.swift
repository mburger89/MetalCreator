import CreatorGraph

/// Copied nodes and the wires between them, with the group definitions the copied group nodes use (every one, however
/// deep), so a paste finds them even after the document lost them, and merges them by content (groups spec §9,
/// `GroupMerge`). Kept in the editor: the slice has one document and MetalUI's pasteboard carries text only.
public struct NodeClipboard: Equatable, Sendable {
    public var nodes: [Node]
    public var links: [Link]
    public var definitions: [GroupID: GroupDefinition] = [:]

    /// Whether there is nothing to paste (the definitions only travel with group nodes).
    public var isEmpty: Bool { nodes.isEmpty }
}
