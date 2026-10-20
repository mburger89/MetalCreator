/// The vector maths the mesh tools share, on `SIMD3<Double>`: the standard library has no cross or dot product, and the `simd`
/// module that has them is Apple's (implicit spec Errata D11).
extension SIMD3 where Scalar == Double {
    func cross(_ other: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(y * other.z - z * other.y, z * other.x - x * other.z, x * other.y - y * other.x)
    }

    func dot(_ other: SIMD3<Double>) -> Double { (self * other).sum() }

    var length: Double { dot(self).squareRoot() }
}
