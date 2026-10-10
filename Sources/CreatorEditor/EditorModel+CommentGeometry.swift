import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Where comments are drawn, what a frame holds, and what a press on one hits (canvas comments spec 2026-10-09 §7).
/// A comment's `frame` is stored left-to-right like a node's position; these read it through the dock's flow.
extension EditorModel {
    /// The note's rectangle in display canvas points.
    public func frame(of note: StickyNote) -> CanvasRect { flow.display(note.frame) }

    /// The comment frame's rectangle in display canvas points.
    public func frame(of box: CommentFrame) -> CanvasRect { flow.display(box.frame) }

    /// The rectangle of comment `id` (a note or a frame) in display canvas points; `nil` if it is gone.
    public func frame(ofComment id: CommentID) -> CanvasRect? {
        graph.stickies[id].map { frame(of: $0) } ?? graph.frames[id].map { frame(of: $0) }
    }

    /// The nodes a frame holds: those whose drawn centre lies inside it. Geometric and never stored, so a node
    /// dragged across the edge simply changes membership.
    public func members(of box: CommentFrame) -> Set<NodeID> {
        let rect = frame(of: box)
        return Set(graph.nodes.values.filter { rect.contains(frame(of: $0).centre) }.map(\.id))
    }

    /// Notes back to front: by ID, with the selected ones raised above the rest.
    public var drawOrderNotes: [StickyNote] {
        graph.stickies.values.sorted { a, b in
            let aSelected = canvasSelection.comments.contains(a.id), bSelected = canvasSelection.comments.contains(b.id)
            return aSelected != bSelected ? bSelected : a.id < b.id
        }
    }

    /// Frames back to front: by ID, with the selected ones raised above the rest.
    public var drawOrderFrames: [CommentFrame] {
        graph.frames.values.sorted { a, b in
            let aSelected = canvasSelection.comments.contains(a.id), bSelected = canvasSelection.comments.contains(b.id)
            return aSelected != bSelected ? bSelected : a.id < b.id
        }
    }

    /// The comment under `point` (display canvas points), topmost first: a selected comment's resize handle, a note
    /// anywhere on its rectangle, then a frame on its title bar or edge band. Notes beat frames, and the selected
    /// raise within their kind, as they draw. `nil` when no comment is there; nodes are tested before this.
    func commentHit(at point: Vector2) -> CanvasHit? {
        for note in drawOrderNotes.reversed() {
            let rect = frame(of: note)
            if canvasSelection.comments.contains(note.id), CommentLayout.handle(of: rect).contains(point) { return .resize(note.id) }
            if rect.contains(point) { return .note(note.id) }
        }
        for box in drawOrderFrames.reversed() {
            let rect = frame(of: box)
            if canvasSelection.comments.contains(box.id), CommentLayout.handle(of: rect).contains(point) { return .resize(box.id) }
            if CommentLayout.chromeContains(rect, point) { return .frame(box.id) }
        }
        return nil
    }

    /// The comments a box (display canvas points) selects: a note whose rectangle meets it, a frame whose chrome
    /// does (`CommentLayout.chromeIntersects`).
    func comments(intersecting rect: CanvasRect) -> Set<CommentID> {
        let notes = graph.stickies.values.filter { frame(of: $0).intersects(rect) }.map(\.id)
        let frames = graph.frames.values.filter { CommentLayout.chromeIntersects(frame(of: $0), rect) }.map(\.id)
        return Set(notes + frames)
    }
}
