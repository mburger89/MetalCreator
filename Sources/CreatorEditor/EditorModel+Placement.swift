import CreatorGeometry
import CreatorGraph

extension EditorModel {
    /// The canvas's frame in window points; `nil` while the panel is hidden or not placed.
    public var canvasFrameInWindow: CanvasRect? {
        guard isPanelVisible, let placement = panelPlacement else { return nil }
        let local = GraphPanelLayout.canvasFrame(inPanelOf: placement.panel.size, flow: flow, showsLibrary: showsLibrary,
                                                 showsRefusal: refusal != nil)
        return CanvasRect(origin: placement.panel.origin + local.origin, size: local.size)
    }

    /// A canvas-local screen point (`pointerLocation`, a press) in window points, or `nil` while unplaced.
    public func windowPoint(fromCanvas point: Vector2) -> Vector2? {
        canvasFrameInWindow.map { $0.origin + point }
    }
}

extension EditorModel {
    /// The clear space kept round a node placed by `freePosition`, in canvas points.
    static let placementGap = 16.0

    /// A node's rectangle in stored (left-to-right) coordinates: the left dock draws the transpose, so its size is swapped here.
    func storedFrame(of node: Node) -> CanvasRect {
        storedFrame(origin: node.position, shape: shape(of: node))
    }

    func storedFrame(origin: Vector2, shape: NodeShape) -> CanvasRect {
        CanvasRect(origin: origin, size: flow.stored(NodeLayout.size(shape)))
    }

    /// Where a new node of `shape` goes, in stored coordinates: `preferred` when its frame, with `placementGap` round it, touches no
    /// node or note of the level shown and none of `taken` (stored rectangles of nodes about to be added with it); else the
    /// nearest spot below it in stored y, which is across the flow in either dock, one node's height at a time, so the new node
    /// lands beside the chain it grows from and never on top of a node already there. Nothing is moved.
    public func freePosition(for shape: NodeShape, near preferred: Vector2, taken: [CanvasRect] = []) -> Vector2 {
        let occupied = graph.nodes.values.map { storedFrame(of: $0) } + graph.stickies.values.map(\.frame) + taken
        let size = flow.stored(NodeLayout.size(shape))
        for step in 0..<200 {
            let origin = preferred + Vector2(0, Double(step) * (size.y + Self.placementGap))
            let candidate = CanvasRect(origin: origin - Vector2(Self.placementGap, Self.placementGap) * 0.5,
                                       size: size + Vector2(Self.placementGap, Self.placementGap))
            if !occupied.contains(where: { $0.intersects(candidate) }) { return origin }
        }
        return preferred
    }

    /// The stored rectangle a node of `shape` placed at `position` would fill; pass it as `taken` when placing the next node.
    public func placedFrame(of shape: NodeShape, at position: Vector2) -> CanvasRect {
        storedFrame(origin: position, shape: shape)
    }
}
