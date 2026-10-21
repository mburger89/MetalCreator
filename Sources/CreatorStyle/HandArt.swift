/// The closed hand of `GrabCursor`, drawn from signed distances: a rounded palm, four knuckles and a thumb in white with a dark
/// outline, anti-aliased by the distance to each edge. Straight (not premultiplied) RGBA, row-major from the top-left, as
/// `ImageBitmap(width:height:rgba:)` takes it.
enum HandArt {
    /// A circle of `radius` at (`x`, `y`) or a rounded box of half-size (`halfWidth`, `halfHeight`) at (`x`, `y`) with corner `radius`.
    private enum Shape {
        case circle(x: Double, y: Double, radius: Double)
        case box(x: Double, y: Double, halfWidth: Double, halfHeight: Double, radius: Double)

        /// Negative inside, positive outside, in pixels.
        func distance(x px: Double, y py: Double) -> Double {
            switch self {
            case let .circle(x, y, radius):
                return ((px - x) * (px - x) + (py - y) * (py - y)).squareRoot() - radius
            case let .box(x, y, halfWidth, halfHeight, radius):
                let dx = abs(px - x) - halfWidth + radius, dy = abs(py - y) - halfHeight + radius
                let outside = (max(dx, 0) * max(dx, 0) + max(dy, 0) * max(dy, 0)).squareRoot()
                return outside + min(max(dx, dy), 0) - radius
            }
        }
    }

    private static let shapes: [Shape] = [
        .box(x: 24, y: 29, halfWidth: 11, halfHeight: 8, radius: 5),
        .circle(x: 15.5, y: 20, radius: 4.6), .circle(x: 21.2, y: 18.6, radius: 4.6),
        .circle(x: 26.8, y: 18.6, radius: 4.6), .circle(x: 32.5, y: 20, radius: 4.6),
        .circle(x: 12.5, y: 28, radius: 4.4),
    ]

    /// Half the outline's width in pixels, and how much of it lies outside the white.
    private static let outline = 1.8

    static func rgba(side: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for row in 0..<side {
            for column in 0..<side {
                let distance = shapes.map { $0.distance(x: Double(column) + 0.5, y: Double(row) + 0.5) }.min() ?? .infinity
                let reach = min(max(0.5 - (distance - outline), 0), 1)   // the hand and its outline
                guard reach > 0 else { continue }
                let fill = min(max(0.5 - distance, 0), 1)                  // the white inside the outline
                let grey = UInt8((255 * fill / reach).rounded())            // dark at the rim, white inside
                let offset = (row * side + column) * 4
                bytes[offset] = grey
                bytes[offset + 1] = grey
                bytes[offset + 2] = grey
                bytes[offset + 3] = UInt8((255 * reach).rounded())
            }
        }
        return bytes
    }
}
