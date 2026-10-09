// Test fixture file: which rect a headless frame paints last at a point.
import CreatorGeometry
import MetalUI

/// The last rect in draw order that paints at `point` (window points): its bounds and its clip both cover the point
/// and it has a visible fill there (or the point is on its visible border). Rects drawn under a transform record map their bounds and local clip through
/// it and are also cut by its outer (screen-space) clip, as the shader does. A stand-in for reading a pixel: the
/// headless frame has no rasterizer, and what paints last at a point is what that pixel shows (fills are opaque here).
func topRect(at point: Vector2, in scene: Scene, scale: Double = 2) -> MUIRect? {
    let x = Float(point.x * scale), y = Float(point.y * scale)
    func covers(_ bounds: MUIBounds) -> Bool {
        x >= bounds.origin.x && x < bounds.origin.x + bounds.size.width
            && y >= bounds.origin.y && y < bounds.origin.y + bounds.size.height
    }
    var top: MUIRect?
    for run in scene.drawList where run.kind == .rect {
        for rect in scene.rects[run.start..<(run.start + run.count)] {
            let widths = rect.borderWidths
            let border = rect.borderColor.a > 0 && max(widths.top, widths.right, widths.bottom, widths.left) > 0
            guard rect.background.a > 0 || border else { continue }
            // A border alone paints a ring: a point in its hollow middle shows what is under it.
            let hollow = MUIBounds(origin: MUIPoint(x: rect.bounds.origin.x + widths.left, y: rect.bounds.origin.y + widths.top),
                                   size: MUISize(width: rect.bounds.size.width - widths.left - widths.right,
                                                 height: rect.bounds.size.height - widths.top - widths.bottom))
            let index = Int(rect.shape >> 8)
            if index > 0, scene.transforms.indices.contains(index - 1) {
                let record = scene.transforms[index - 1]
                guard covers(record.outerMask), covers(mapped(rect.bounds, record)),
                      covers(mapped(rect.contentMask, record)),
                      rect.background.a > 0 || !covers(mapped(hollow, record)) else { continue }
            } else {
                guard covers(rect.bounds), covers(rect.contentMask), rect.background.a > 0 || !covers(hollow) else { continue }
            }
            top = rect
        }
    }
    return top
}

/// `bounds` through `record`'s affine, as its bounding box.
private func mapped(_ bounds: MUIBounds, _ record: MUITransform) -> MUIBounds {
    let xs = [bounds.origin.x, bounds.origin.x + bounds.size.width]
    let ys = [bounds.origin.y, bounds.origin.y + bounds.size.height]
    let corners = xs.flatMap { x in ys.map { y in (record.a * x + record.c * y + record.tx, record.b * x + record.d * y + record.ty) } }
    let minX = corners.map(\.0).min() ?? 0, maxX = corners.map(\.0).max() ?? 0
    let minY = corners.map(\.1).min() ?? 0, maxY = corners.map(\.1).max() ?? 0
    return MUIBounds(origin: MUIPoint(x: minX, y: minY), size: MUISize(width: maxX - minX, height: maxY - minY))
}
