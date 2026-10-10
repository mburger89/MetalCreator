import CreatorGraph

/// What the canvas draws to edit a comment in place: the edit, and the rectangle of its field in display canvas
/// points (a note's whole rectangle, a frame's title bar), under the canvas's own pan and zoom.
public struct CommentEditor: Equatable, Sendable {
    public var edit: CommentEdit
    public var rect: CanvasRect
}
