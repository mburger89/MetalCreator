import CreatorGeometry
import CreatorStyle
import MetalUI

/// One wire: a stroked `WireShape` (its route's pieces) in a frame just big enough for them, offset to its place on the
/// canvas.
struct WireView: Component, Equatable {
    static let defaultLineWidth = 2.0

    let pieces: [WireGeometry]
    let color: HexColor
    let lineWidth: Double

    init(pieces: [WireGeometry], color: HexColor, lineWidth: Double = WireView.defaultLineWidth) {
        self.pieces = pieces
        self.color = color
        self.lineWidth = lineWidth
    }

    /// A wire of one piece: the wire being dragged, or an untied wire.
    init(geometry: WireGeometry, color: HexColor, lineWidth: Double = WireView.defaultLineWidth) {
        self.init(pieces: [geometry], color: color, lineWidth: lineWidth)
    }

    var content: some ElementGroup {
        let bounds = WireGeometry.bounds(of: pieces, padding: lineWidth * 2)
        return WireShape(pieces, origin: bounds.origin)
            .stroke(color.color, lineWidth: lineWidth.px)
            .frame(width: bounds.size.x.px, height: bounds.size.y.px)
            .offset(x: bounds.origin.x.px, y: bounds.origin.y.px)
    }
}
