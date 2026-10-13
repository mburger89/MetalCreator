/// A decoded picture as grey values (fields spec §5): `width` × `height` pixels of 16-bit grey, row 0 at the top, in one flat
/// array, so copies are cheap and a field holding one costs `byteCount`. Made by `GreyImageDecoder` (CreatorNodes), which is
/// the only reader of image files; this type is plain data and maths.
public struct GreyImage: Sendable {
    public let width: Int
    public let height: Int
    /// Row-major grey values, 0 black to 65,535 white.
    public let pixels: [UInt16]

    /// `nil` unless both sides are at least 1 and `pixels` has exactly `width * height` values.
    public init?(width: Int, height: Int, pixels: [UInt16]) {
        let (count, overflow) = width.multipliedReportingOverflow(by: height)
        guard width >= 1, height >= 1, !overflow, pixels.count == count else { return nil }
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Memory the pixels take.
    public var byteCount: Int { pixels.count * MemoryLayout<UInt16>.stride }

    /// The grey value in 0…1 at picture coordinates `u` (0 left edge, 1 right edge) and `v` (0 top edge, 1 bottom edge),
    /// bilinear between pixel centres. Outside 0…1 the picture repeats or holds its edge pixels, as `edges` says. A
    /// coordinate that is NaN or infinite gives 0, and no finite one can trap: positions are folded into the picture while
    /// still `Double`s. A finite `u` or `v` so large that scaling by the size overflows to infinity (a magnitude over
    /// `Double.greatestFiniteMagnitude` ÷ the side in pixels) also gives 0, not a pixel.
    public func value(u: Double, v: Double, edges: ImageEdges) -> Double {
        let x = u * Double(width) - 0.5, y = v * Double(height) - 0.5
        guard x.isFinite, y.isFinite else { return 0 }
        let columns = Self.taps(x, count: width, edges: edges), rows = Self.taps(y, count: height, edges: edges)
        let top = Self.mix(grey(columns.low, rows.low), grey(columns.high, rows.low), columns.fraction)
        let bottom = Self.mix(grey(columns.low, rows.high), grey(columns.high, rows.high), columns.fraction)
        return Self.mix(top, bottom, rows.fraction) / 65_535
    }

    private func grey(_ x: Int, _ y: Int) -> Double { Double(pixels[y * width + x]) }

    private static func mix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    /// The two pixels along one axis that a position (in pixels, centres at whole numbers) lies between, and how far towards
    /// the second.
    private static func taps(_ position: Double, count: Int, edges: ImageEdges) -> (low: Int, high: Int, fraction: Double) {
        let size = Double(count)
        switch edges {
        case .tile:
            let folded = position - (position / size).rounded(.down) * size
            let held = min(max(folded, 0), size.nextDown)
            let low = Int(held.rounded(.down))
            return (low, (low + 1) % count, held - Double(low))
        case .clamp:
            let held = min(max(position, 0), size - 1)
            let low = Int(held.rounded(.down))
            return (low, min(low + 1, count - 1), held - Double(low))
        }
    }
}
