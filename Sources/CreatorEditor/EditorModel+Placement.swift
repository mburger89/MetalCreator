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
