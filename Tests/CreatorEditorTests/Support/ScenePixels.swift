// Test fixture file: which rect a headless frame paints last at a point.
import CreatorGeometry
import MetalUI

/// The last rect in draw order that paints at `point` (window points): its bounds and its clip both cover the point
/// and it has a visible fill there (or the point is on its visible border). Rects drawn under a transform record map their bounds and local clip through
/// it and are also cut by its outer (screen-space) clip, as the shader does. A stand-in for reading a pixel: the
/// headless frame has no rasterizer, and what paints last at a point is what that pixel shows (fills are opaque here).
func topRect(at point: Vector2, in scene: Scene, scale: Double = 2) -> MUIRect? {
    topRect(at: point, in: scene, scale: scale, isGroupContent: false)
}

/// `topRect(at:in:scale:)` over `scene`'s runs in draw order. A `group` run (MetalUI's offscreen group, which a clipped
/// or masked view can become) holds its leaves in `groupScenes[run.start]`, in the parent's coordinates; they are
/// searched where the group's box covers the point (the mask is not applied: the points tests ask about lie inside
/// the masked shape). A rect found inside a group is returned with its transform baked into its bounds (and its
/// transform index cleared), since `screenFrame(of:in:)` reads the root scene's transforms.
private func topRect(at point: Vector2, in scene: Scene, scale: Double, isGroupContent: Bool) -> MUIRect? {
    let x = Float(point.x * scale), y = Float(point.y * scale)
    func covers(_ bounds: MUIBounds) -> Bool {
        x >= bounds.origin.x && x < bounds.origin.x + bounds.size.width
            && y >= bounds.origin.y && y < bounds.origin.y + bounds.size.height
    }
    var top: MUIRect?
    for run in scene.drawList {
        if run.kind == .group {
            for index in run.start..<(run.start + run.count) where scene.groups.indices.contains(index) {
                guard covers(scene.groups[index].bounds), scene.groupScenes.indices.contains(index),
                      let inner = topRect(at: point, in: scene.groupScenes[index], scale: scale, isGroupContent: true)
                else { continue }
                top = inner
            }
            continue
        }
        guard run.kind == .rect else { continue }
        for rect in scene.rects[run.start..<(run.start + run.count)] {
            if let found = hit(rect, in: scene, covers: covers, isGroupContent: isGroupContent) { top = found }
        }
    }
    return top
}

/// `rect` if it paints at the point `covers` tests (see `topRect`), else `nil`.
private func hit(_ rect: MUIRect, in scene: Scene, covers: (MUIBounds) -> Bool, isGroupContent: Bool) -> MUIRect? {
    let widths = rect.borderWidths
    let border = rect.borderColor.a > 0 && max(widths.top, widths.right, widths.bottom, widths.left) > 0
    guard rect.background.a > 0 || border else { return nil }
    // A border alone paints a ring: a point in its hollow middle shows what is under it.
    let hollow = MUIBounds(origin: MUIPoint(x: rect.bounds.origin.x + widths.left, y: rect.bounds.origin.y + widths.top),
                           size: MUISize(width: rect.bounds.size.width - widths.left - widths.right,
                                         height: rect.bounds.size.height - widths.top - widths.bottom))
    let index = Int(rect.shape >> 8)
    guard index > 0, scene.transforms.indices.contains(index - 1) else {
        guard covers(rect.bounds), covers(rect.contentMask), rect.background.a > 0 || !covers(hollow) else { return nil }
        return rect
    }
    let record = scene.transforms[index - 1]
    guard covers(record.outerMask), covers(mapped(rect.bounds, record)), covers(mapped(rect.contentMask, record)),
          rect.background.a > 0 || !covers(mapped(hollow, record)) else { return nil }
    var found = rect
    if isGroupContent {
        found.bounds = mapped(rect.bounds, record)
        found.shape &= 0xFF
    }
    return found
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
