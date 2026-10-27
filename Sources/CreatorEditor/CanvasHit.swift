import CreatorGraph
import CreatorKernel

/// What lies under a point on the canvas (cable ties spec 2026-10-26 §4.1). Topmost first: a socket, a tie's band, a node,
/// a note (a selected one's resize handle first), a wire, a frame's chrome (a selected one's handle first), then empty
/// canvas.
public enum CanvasHit: Equatable, Sendable {
    case socket(SocketRef)
    /// A cable tie, anywhere on its band.
    case tie(TieID)
    case node(NodeID)
    /// A sticky note, anywhere on its rectangle.
    case note(CommentID)
    /// A wire within `EditorModel.wireHitDistance` of its taut route, named by its input endpoint.
    case wire(Endpoint)
    /// A comment frame, on its title bar or its edge band only.
    case frame(CommentID)
    /// The bottom-right handle of a selected comment: a press drags its size.
    case resize(CommentID)
    case empty
}
