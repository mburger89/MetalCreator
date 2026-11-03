/// A 3MF transform (core specification, 3D Model): twelve numbers `m00 m01 m02 m10 m11 m12 m20 m21 m22 m30 m31 m32`, the rows of a
/// 4×3 matrix, applied to a point as a row vector: `x' = m00·x + m10·y + m20·z + m30`, `y' = m01·x + m11·y + m21·z + m31` and
/// `z' = m02·x + m12·y + m22·z + m32`. So `rows[0]` is where the x axis goes (the numbers m00 m01 m02), `rows[1]` the y axis,
/// `rows[2]` the z axis, and `offset` is the translation (m30 m31 m32). Kept in `Double`, in file units.
struct ThreeMFTransform {
    var row0: SIMD3<Double>
    var row1: SIMD3<Double>
    var row2: SIMD3<Double>
    var offset: SIMD3<Double>

    static let identity = ThreeMFTransform(row0: SIMD3(1, 0, 0), row1: SIMD3(0, 1, 0), row2: SIMD3(0, 0, 1), offset: .zero)

    /// The twelve numbers in the file's order.
    init(_ numbers: [Double]) {
        row0 = SIMD3(numbers[0], numbers[1], numbers[2])
        row1 = SIMD3(numbers[3], numbers[4], numbers[5])
        row2 = SIMD3(numbers[6], numbers[7], numbers[8])
        offset = SIMD3(numbers[9], numbers[10], numbers[11])
    }

    init(row0: SIMD3<Double>, row1: SIMD3<Double>, row2: SIMD3<Double>, offset: SIMD3<Double>) {
        (self.row0, self.row1, self.row2, self.offset) = (row0, row1, row2, offset)
    }

    /// The determinant of the 3×3 part: negative when the transform mirrors.
    var determinant: Double { row0.x * (row1.y * row2.z - row1.z * row2.y) - row0.y * (row1.x * row2.z - row1.z * row2.x)
        + row0.z * (row1.x * row2.y - row1.y * row2.x) }

    /// Whether every number is finite and the transform can be undone.
    var isInvertible: Bool {
        let all = [row0, row1, row2, offset]
        let finite = all.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }
        let det = determinant
        return finite && det.isFinite && det != 0
    }

    func apply(_ p: SIMD3<Double>) -> SIMD3<Double> {
        row0 * p.x + row1 * p.y + row2 * p.z + offset
    }

    private func turn(_ v: SIMD3<Double>) -> SIMD3<Double> { row0 * v.x + row1 * v.y + row2 * v.z }

    /// The transform that does `self` and then `next`: a component's transform followed by its parent's.
    func then(_ next: ThreeMFTransform) -> ThreeMFTransform {
        ThreeMFTransform(row0: next.turn(row0), row1: next.turn(row1), row2: next.turn(row2), offset: next.apply(offset))
    }
}
