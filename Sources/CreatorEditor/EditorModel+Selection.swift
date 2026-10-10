import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Selecting what is on the canvas (spec 2026-10-09 §3). Every gesture and key acts through these members: a click
/// and a box combine `items(for:)` and `items(intersecting:)` with the selection by a `SelectionMode`, ⌘A is
/// `allItems`, a drag and an arrow key move `positions(of:)` by `moveCommands(from:by:)`, an ⌥-drag copies
/// `SelectionPositions.items`, and F frames `bounds(of:)`. Canvas comments (sub-project B) are items of the same
/// selection: notes and frames are in `CanvasSelection.comments` and the hits `CanvasHit.note` and `.frame`, so no
/// caller changes.
extension EditorModel {
    /// Combines `items` with the selection as `mode` says.
    public func select(_ items: CanvasSelection, mode: SelectionMode) {
        canvasSelection = canvasSelection.applying(items, mode: mode)
    }

    /// ⌘A: everything on the canvas.
    public func selectAll() {
        canvasSelection = allItems
    }

    /// Esc, or a plain click on empty canvas: nothing selected.
    public func clearSelection() {
        canvasSelection = CanvasSelection()
    }

    /// Everything on the canvas: every node and every comment.
    public var allItems: CanvasSelection {
        CanvasSelection(nodes: Set(graph.nodes.keys), comments: graph.commentIDs)
    }

    /// What a press on `hit` selects: the node, or a socket's node, or the comment; `nil` for empty canvas.
    public func items(for hit: CanvasHit) -> CanvasSelection? {
        switch hit {
        case .node(let id): CanvasSelection(nodes: [id])
        case .socket(let socket): CanvasSelection(nodes: [socket.endpoint.node])
        case .note(let id), .frame(let id), .resize(let id): CanvasSelection(comments: [id])
        case .empty: nil
        }
    }

    /// What a box covers: the nodes and notes whose drawn rectangle meets `rect` (display canvas points) and the
    /// frames whose chrome does.
    public func items(intersecting rect: CanvasRect) -> CanvasSelection {
        CanvasSelection(nodes: nodes(intersecting: rect), comments: comments(intersecting: rect))
    }

    /// Where `items` are now (stored coordinates; a comment's is its frame's origin), skipping any no longer on the
    /// canvas.
    public func positions(of items: CanvasSelection) -> SelectionPositions {
        SelectionPositions(
            nodes: Dictionary(uniqueKeysWithValues: items.nodes.compactMap { id in
                graph.nodes[id].map { (id, $0.position) }
            }),
            comments: Dictionary(uniqueKeysWithValues: items.comments.compactMap { id in
                (graph.stickies[id]?.frame.origin ?? graph.frames[id]?.frame.origin).map { (id, $0) }
            }))
    }

    /// The commands that put every item of `start` at its position there plus `delta` (stored coordinates), in a
    /// stable order: the nodes by ID, then the comments by ID. A comment that is gone is skipped.
    public func moveCommands(from start: SelectionPositions, by delta: Vector2) -> [GraphCommand] {
        let nodeMoves = start.nodes.keys.sorted().compactMap { id in
            start.nodes[id].map { GraphCommand.move(id, to: $0 + delta) }
        }
        let commentMoves = start.comments.keys.sorted().compactMap { id -> GraphCommand? in
            guard let origin = start.comments[id] else { return nil }
            if var note = graph.stickies[id] {
                note.frame.origin = origin + delta
                return .setSticky(note)
            }
            guard var box = graph.frames[id] else { return nil }
            box.frame.origin = origin + delta
            return .setFrame(box)
        }
        return nodeMoves + commentMoves
    }

    /// The smallest rectangle (display canvas points) around the drawn rectangles of those `items` still on the
    /// canvas, comments included; `nil` when there are none.
    public func bounds(of items: CanvasSelection) -> CanvasRect? {
        let frames = items.nodes.compactMap { graph.nodes[$0] }.map { frame(of: $0) }
            + items.comments.sorted().compactMap { frame(ofComment: $0) }
        guard let first = frames.first else { return nil }
        return frames.dropFirst().reduce(first) { $0.union($1) }
    }
}
