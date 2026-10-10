import CreatorGeometry
import CreatorGraph

extension EditorModel {
    /// Comment `id`'s rectangle in stored coordinates, whichever kind it is; `nil` if it is gone.
    func storedFrame(ofComment id: CommentID) -> CanvasRect? {
        graph.stickies[id]?.frame ?? graph.frames[id]?.frame
    }

    /// The command that gives comment `id` the size it has at `start` plus a pointer move of `displayDelta` (display
    /// canvas points): the top-left corner is fixed, and the size is at least `CommentLayout.minimumSize` as drawn.
    /// The left dock draws the transpose, so the size is worked out as drawn and stored back. `nil` for a comment
    /// that is gone.
    func resizeCommand(_ id: CommentID, from start: CanvasRect, by displayDelta: Vector2) -> GraphCommand? {
        let size = flow.stored(CommentLayout.clamped(flow.display(start.size) + displayDelta))
        let frame = CanvasRect(origin: start.origin, size: size)
        if var note = graph.stickies[id] {
            note.frame = frame
            return .setSticky(note)
        }
        guard var box = graph.frames[id] else { return nil }
        box.frame = frame
        return .setFrame(box)
    }
}
