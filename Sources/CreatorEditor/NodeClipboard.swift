import CreatorGraph

/// Copied nodes and the wires between them. Kept in the editor: the slice has one document
/// and MetalUI's pasteboard carries text only.
public struct NodeClipboard: Equatable, Sendable {
    public var nodes: [Node]
    public var links: [Link]
}
