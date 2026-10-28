import MetalUI

/// The arrowheads of a dimension as closed triangles, in the view's coordinates; filled by the view.
struct DimensionArrowsShape: Shape, Hashable {
    var arrows: [PlacedDimension.Arrow]
    var length: Double
    var width: Double

    func path(in rect: Bounds<Pixels>) -> Path {
        Path { path in
            for arrow in arrows {
                let corners = arrow.corners(length: length, width: width).map(DimensionLinesShape.point)
                guard let first = corners.first else { continue }
                path.move(to: first)
                for corner in corners.dropFirst() { path.addLine(to: corner) }
                path.closeSubpath()
            }
        }
    }
}
