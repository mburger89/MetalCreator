import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Selecting what is on the canvas (spec 2026-10-09 §3). Every gesture and key acts through these members: a click
/// and a box combine `items(for:)` and `items(intersecting:)` with the selection by a `SelectionMode`, ⌘A is
/// `allItems`, a drag and an arrow key move `positions(of:)` by `moveCommands(from:by:)`, an ⌥-drag copies
/// `SelectionPositions.items`, and F frames `bounds(of:)`. Canvas comments (sub-project B) join by adding their items
/// to `CanvasSelection`, `SelectionPositions`, `CanvasHit` and the members marked "B adds"; no caller changes.
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

    /// Everything on the canvas. B adds: every comment.
    public var allItems: CanvasSelection {
        CanvasSelection(nodes: Set(graph.nodes.keys))
    }

    /// What a press on `hit` selects: the node, or a socket's node; `nil` for empty canvas. B adds: a comment.
    public func items(for hit: CanvasHit) -> CanvasSelection? {
        switch hit {
        case .node(let id): CanvasSelection(nodes: [id])
        case .socket(let socket): CanvasSelection(nodes: [socket.endpoint.node])
        case .empty: nil
        }
    }

    /// What a box covers: the items whose drawn rectangle meets `rect` (display canvas points). B adds: comments.
    public func items(intersecting rect: CanvasRect) -> CanvasSelection {
        CanvasSelection(nodes: nodes(intersecting: rect))
    }

    /// Where `items` are now (stored coordinates), skipping any no longer on the canvas. B adds: comments.
    public func positions(of items: CanvasSelection) -> SelectionPositions {
        SelectionPositions(nodes: Dictionary(uniqueKeysWithValues: items.nodes.compactMap { id in
            graph.nodes[id].map { (id, $0.position) }
        }))
    }

    /// The commands that put every item of `start` at its position there plus `delta` (stored coordinates), in a
    /// stable order. B adds: comment moves.
    public func moveCommands(from start: SelectionPositions, by delta: Vector2) -> [GraphCommand] {
        start.nodes.keys.sorted().compactMap { id in
            start.nodes[id].map { GraphCommand.move(id, to: $0 + delta) }
        }
    }

    /// The smallest rectangle (display canvas points) around the drawn rectangles of those `items` still on the
    /// canvas; `nil` when there are none. B adds: comment rectangles.
    public func bounds(of items: CanvasSelection) -> CanvasRect? {
        let frames = items.nodes.compactMap { graph.nodes[$0] }.map { frame(of: $0) }
        guard let first = frames.first else { return nil }
        return frames.dropFirst().reduce(first) { $0.union($1) }
    }
}
