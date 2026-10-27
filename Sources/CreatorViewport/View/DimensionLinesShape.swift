import MetalUI

/// Every segment of a dimension (dimension, extension and leader lines), in the view's coordinates; stroked by the view.
struct DimensionLinesShape: Shape, Hashable {
    var segments: [ScreenSegment]

    func path(in rect: Bounds<Pixels>) -> Path {
        Path { path in
            for segment in segments {
                path.move(to: Self.point(segment.a))
                path.addLine(to: Self.point(segment.b))
            }
        }
    }

    static func point(_ p: ScreenPoint) -> Point<Pixels> { Point(x: Pixels(Float(p.x)), y: Pixels(Float(p.y))) }
}
