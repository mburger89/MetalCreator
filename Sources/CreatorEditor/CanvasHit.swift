import CreatorGraph
import CreatorKernel

/// What lies under a point on the canvas, topmost first: a socket beats its node, a node beats the comments, a note
/// beats a frame (canvas comments spec 2026-10-09 §7).
public enum CanvasHit: Equatable, Sendable {
    case socket(SocketRef)
    case node(NodeID)
    /// A sticky note, anywhere on its rectangle.
    case note(CommentID)
    /// A comment frame, on its title bar or its edge band only.
    case frame(CommentID)
    /// The bottom-right handle of a selected comment: a press drags its size.
    case resize(CommentID)
    case empty
}
