import CreatorGraph

/// Copied nodes and the wires between them, and copied canvas comments. Kept in the editor: the slice has one
/// document and MetalUI's pasteboard carries text only.
public struct NodeClipboard: Equatable, Sendable {
    public var nodes: [Node]
    public var links: [Link]
    public var stickies: [StickyNote] = []
    public var frames: [CommentFrame] = []

    /// Whether there is nothing to paste.
    public var isEmpty: Bool { nodes.isEmpty && stickies.isEmpty && frames.isEmpty }
}
