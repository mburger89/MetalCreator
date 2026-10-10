import CreatorGeometry
import CreatorGraph

extension CanvasFlow {
    /// A stored (left-to-right) rectangle as drawn in this flow: the left dock shows its transpose, origin and size
    /// alike, so a frame keeps around the nodes it held when the dock changes.
    public func display(_ stored: CanvasRect) -> CanvasRect {
        CanvasRect(origin: display(stored.origin), size: display(stored.size))
    }

    /// A drawn rectangle back in stored coordinates; the transpose is its own inverse.
    public func stored(_ display: CanvasRect) -> CanvasRect { self.display(display) }
}
