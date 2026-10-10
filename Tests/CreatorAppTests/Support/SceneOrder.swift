// Test fixture file: reading a headless frame's paint order and rect frames.
import CreatorEditor
import CreatorGeometry
import CreatorGraph
import MetalUI

/// Where a primitive is in the frame's paint order: its index in the finalized `drawList`'s runs, all kinds
/// together, so a rect can be compared with the viewport's surface. `nil` if no run holds it.
func paintPosition(of kind: PrimitiveKind, at index: Int, in scene: Scene) -> Int? {
    var position = 0
    for run in scene.drawList {
        if run.kind == kind, (run.start..<run.start + run.count).contains(index) { return position + index - run.start }
        position += run.count
    }
    return nil
}

/// A rect's frame in window points (the frame's rects here carry no transform).
func frame(of rect: MUIRect, scale: Double = 2) -> CanvasRect { frame(of: rect.bounds, scale: scale) }

/// Device-pixel bounds in window points.
func frame(of bounds: MUIBounds, scale: Double = 2) -> CanvasRect {
    CanvasRect(origin: Vector2(Double(bounds.origin.x) / scale, Double(bounds.origin.y) / scale),
               size: Vector2(Double(bounds.size.width) / scale, Double(bounds.size.height) / scale))
}
