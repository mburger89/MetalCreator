import CreatorGeometry

extension EditorModel {
    /// The panel's placement in its window, from the host; `nil` without a host (headless tests) or before the
    /// window has a size.
    public var panelPlacement: PanelPlacement? { placement?() }

    /// The canvas's frame in window points; `nil` while the panel is hidden or not placed.
    public var canvasFrameInWindow: CanvasRect? {
        guard isPanelVisible, let placement = panelPlacement else { return nil }
        let local = GraphPanelLayout.canvasFrame(inPanelOf: placement.panel.size, flow: flow, showsLibrary: showsLibrary)
        return CanvasRect(origin: placement.panel.origin + local.origin, size: local.size)
    }

    /// A canvas-local screen point (`pointerLocation`, a press) in window points, or `nil` while unplaced.
    public func windowPoint(fromCanvas point: Vector2) -> Vector2? {
        canvasFrameInWindow.map { $0.origin + point }
    }
}
