import CreatorGeometry
import MetalUI

/// One wire: a stroked `WireShape` in a frame just big enough for the curve, offset to its
/// place on the canvas.
struct WireView: Component {
    let geometry: WireGeometry
    let color: HexColor
    var lineWidth = 2.0

    var content: some ElementGroup {
        let bounds = geometry.bounds(padding: lineWidth * 2)
        return WireShape(geometry, origin: bounds.origin)
            .stroke(color.color, lineWidth: lineWidth.px)
            .frame(width: bounds.size.x.px, height: bounds.size.y.px)
            .offset(x: bounds.origin.x.px, y: bounds.origin.y.px)
    }
}
