import CreatorGraph
import CreatorKernel

/// What a click can be paired on to make a double click (`EditorModel+DoubleClick`): a node's body, a note, or a
/// frame's title bar.
enum ClickTarget: Hashable, Sendable {
    case node(NodeID)
    case note(CommentID)
    case frameTitle(CommentID)
}
