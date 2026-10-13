import CreatorGeometry

/// A translucent quad through the scene showing a field on a grid (fields spec §6, "Slice plane"). The host makes one and the
/// viewport draws it: a quad of `halfWidth × halfHeight` millimetres about `origin` spanned by the unit vectors `xAxis` and
/// `yAxis`, coloured from `values` by `ramp`. `values` is one number per grid sample, row-major, `columns` to a row, row 0 at
/// the `-yAxis` edge and column 0 at the `-xAxis` edge; a sample stands for the centre of its texel (`samplePoints()`).
///
/// A grid can be 65,536 numbers, so a slice is equal to another when everything but `values` is and their `generation`s are:
/// the host bumps `generation` each time it changes `values`, and neither `ViewportModel` nor the render key ever compares or
/// hashes the numbers themselves.
public struct ViewportSlice: Hashable, Sendable {
    public var origin: Vector3
    public var xAxis: Vector3
    public var yAxis: Vector3
    public var halfWidth: Double
    public var halfHeight: Double
    public var columns: Int
    public var rows: Int
    public var values: [Float]
    public var ramp: FieldRamp
    /// How much of the quad's colour replaces what is behind it, 0…1.
    public var opacity: Float
    public var generation: Int

    public init(origin: Vector3, xAxis: Vector3, yAxis: Vector3, halfWidth: Double, halfHeight: Double, columns: Int, rows: Int,
                values: [Float], ramp: FieldRamp, opacity: Float = 0.85, generation: Int = 0) {
        self.origin = origin
        self.xAxis = xAxis
        self.yAxis = yAxis
        self.halfWidth = halfWidth
        self.halfHeight = halfHeight
        self.columns = columns
        self.rows = rows
        self.values = values
        self.ramp = ramp
        self.opacity = opacity
        self.generation = generation
    }

    /// True when the grid has a sample to draw and `values` is one per sample.
    public var isValid: Bool { columns > 0 && rows > 0 && values.count == columns * rows }

    /// The world position of every grid sample, in `values`' order: the centre of each texel, so the field sampled there and
    /// drawn with a bilinear lookup lines up with the quad's corners.
    public func samplePoints() -> [Vector3] {
        guard columns > 0, rows > 0 else { return [] }
        return (0..<rows).flatMap { row -> [Vector3] in
            let up = (2 * (Double(row) + 0.5) / Double(rows) - 1) * halfHeight
            return (0..<columns).map { column in
                let across = (2 * (Double(column) + 0.5) / Double(columns) - 1) * halfWidth
                return origin + xAxis * across + yAxis * up
            }
        }
    }

    public static func == (lhs: ViewportSlice, rhs: ViewportSlice) -> Bool {
        lhs.generation == rhs.generation && lhs.origin == rhs.origin && lhs.xAxis == rhs.xAxis && lhs.yAxis == rhs.yAxis
            && lhs.halfWidth == rhs.halfWidth && lhs.halfHeight == rhs.halfHeight && lhs.columns == rhs.columns
            && lhs.rows == rhs.rows && lhs.ramp == rhs.ramp && lhs.opacity == rhs.opacity
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(generation)
        hasher.combine(origin)
        hasher.combine(xAxis)
        hasher.combine(yAxis)
        hasher.combine(halfWidth)
        hasher.combine(halfHeight)
        hasher.combine(columns)
        hasher.combine(rows)
        hasher.combine(ramp)
        hasher.combine(opacity)
    }
}
