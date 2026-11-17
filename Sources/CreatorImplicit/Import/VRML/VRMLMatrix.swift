import Foundation

/// An affine transform of space, applied to a column vector: `apply(p)` is `x·p.x + y·p.y + z·p.z + t`. `a * b` moves by `b` first.
struct VRMLMatrix {
    var x: SIMD3<Double>
    var y: SIMD3<Double>
    var z: SIMD3<Double>
    var t: SIMD3<Double>

    static let identity = VRMLMatrix(x: [1, 0, 0], y: [0, 1, 0], z: [0, 0, 1], t: [0, 0, 0])

    static func translation(_ v: SIMD3<Double>) -> VRMLMatrix {
        VRMLMatrix(x: [1, 0, 0], y: [0, 1, 0], z: [0, 0, 1], t: v)
    }

    static func scale(_ v: SIMD3<Double>) -> VRMLMatrix {
        VRMLMatrix(x: [v.x, 0, 0], y: [0, v.y, 0], z: [0, 0, v.z], t: [0, 0, 0])
    }

    /// Rotation by `angle` radians about `axis` (right-handed). A zero axis is no rotation.
    static func rotation(axis: SIMD3<Double>, angle: Double) -> VRMLMatrix {
        let length = (axis * axis).sum().squareRoot()
        guard length > 0, length.isFinite else { return .identity }
        let k = axis / length
        let cosine = angle.cos
        let sine = angle.sin
        func rotated(_ v: SIMD3<Double>) -> SIMD3<Double> {
            let cross = SIMD3(k.y * v.z - k.z * v.y, k.z * v.x - k.x * v.z, k.x * v.y - k.y * v.x)
            return v * cosine + cross * sine + k * ((k * v).sum() * (1 - cosine))
        }
        return VRMLMatrix(x: rotated([1, 0, 0]), y: rotated([0, 1, 0]), z: rotated([0, 0, 1]), t: [0, 0, 0])
    }

    /// A row-vector matrix as VRML 1's `MatrixTransform` writes it (16 numbers, row-major, `p' = p · M`).
    init?(rowMajor n: [Float]) {
        guard n.count == 16 else { return nil }
        let d = n.map(Double.init)
        self.init(x: [d[0], d[1], d[2]], y: [d[4], d[5], d[6]], z: [d[8], d[9], d[10]], t: [d[12], d[13], d[14]])
    }

    init(x: SIMD3<Double>, y: SIMD3<Double>, z: SIMD3<Double>, t: SIMD3<Double>) {
        self.x = x
        self.y = y
        self.z = z
        self.t = t
    }

    func linear(_ v: SIMD3<Double>) -> SIMD3<Double> { x * v.x + y * v.y + z * v.z }

    func apply(_ p: SIMD3<Double>) -> SIMD3<Double> { linear(p) + t }

    static func * (a: VRMLMatrix, b: VRMLMatrix) -> VRMLMatrix {
        VRMLMatrix(x: a.linear(b.x), y: a.linear(b.y), z: a.linear(b.z), t: a.apply(b.t))
    }

    static func *= (a: inout VRMLMatrix, b: VRMLMatrix) { a = a * b }

    /// Negative when the transform mirrors, which turns triangles inside out.
    var determinant: Double {
        let cross = SIMD3(y.y * z.z - y.z * z.y, y.z * z.x - y.x * z.z, y.x * z.y - y.y * z.x)
        return (x * cross).sum()
    }

    /// `T · C · R · SR · S · SR⁻¹ · C⁻¹`, the fields of VRML's `Transform` (each `nil` is its default).
    static func transform(translation: [Float]?, rotation: [Float]?, scale: [Float]?, scaleOrientation: [Float]?,
                          center: [Float]?) -> VRMLMatrix {
        func vector(_ values: [Float]?, default fallback: SIMD3<Double>) -> SIMD3<Double> {
            guard let values, values.count >= 3 else { return fallback }
            return SIMD3(Double(values[0]), Double(values[1]), Double(values[2]))
        }
        func turn(_ values: [Float]?, sign: Double) -> VRMLMatrix {
            guard let values, values.count >= 4 else { return .identity }
            return .rotation(axis: SIMD3(Double(values[0]), Double(values[1]), Double(values[2])), angle: sign * Double(values[3]))
        }
        let centre = vector(center, default: .zero)
        return .translation(vector(translation, default: .zero)) * .translation(centre) * turn(rotation, sign: 1)
            * turn(scaleOrientation, sign: 1) * .scale(vector(scale, default: [1, 1, 1])) * turn(scaleOrientation, sign: -1)
            * .translation(-centre)
    }
}

private extension Double {
    var cos: Double { Foundation.cos(self) }
    var sin: Double { Foundation.sin(self) }
}
