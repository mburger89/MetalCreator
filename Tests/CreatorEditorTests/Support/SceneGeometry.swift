// Test fixture file: where a headless frame's primitives land on screen.
import CreatorEditor
import CreatorGeometry
import MetalUI

/// A rect's frame on screen, in points: its bounds through its transform when it has one (ruling GX-F: a
/// transformed primitive's bounds are local; `x' = a x + c y + tx`). Exact for translations, which is all the
/// palette and the canvas's unzoomed layers use.
func screenFrame(of rect: MUIRect, in scene: Scene, scale: Double = 2) -> CanvasRect {
    var x = Double(rect.bounds.origin.x), y = Double(rect.bounds.origin.y)
    let index = Int(rect.shape >> 8)
    if index > 0, scene.transforms.indices.contains(index - 1) {
        let t = scene.transforms[index - 1]
        (x, y) = (Double(t.a) * x + Double(t.c) * y + Double(t.tx), Double(t.b) * x + Double(t.d) * y + Double(t.ty))
    }
    return CanvasRect(origin: Vector2(x / scale, y / scale),
                      size: Vector2(Double(rect.bounds.size.width) / scale, Double(rect.bounds.size.height) / scale))
}
