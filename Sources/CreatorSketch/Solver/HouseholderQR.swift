/// Least squares by Householder QR, used for every Levenberg–Marquardt step.
enum HouseholderQR {
    /// Solves min ‖A x − b‖ for `a` with at least as many rows as columns. Returns `nil` when
    /// `a` is rank deficient (a pivot at or below `relativeTolerance` times the largest column
    /// norm, so rounding residue counts as zero), which the damped LM system never is.
    static let relativeTolerance = 1e-12

    static func leastSquares(_ a: DenseMatrix, _ b: [Double]) -> [Double]? {
        var r = a
        var y = b
        let (m, n) = (a.rows, a.columns)
        guard m >= n, b.count == m else { return nil }
        let tolerance = relativeTolerance * largestColumnNorm(a)
        for k in 0..<n {
            var norm = 0.0
            for i in k..<m { norm += r[i, k] * r[i, k] }
            norm = norm.squareRoot()
            guard norm > tolerance else { return nil }
            let alpha = r[k, k] > 0 ? -norm : norm
            var v = Array(repeating: 0.0, count: m - k)
            for i in k..<m { v[i - k] = r[i, k] }
            v[0] -= alpha
            var vNorm = 0.0
            for value in v { vNorm += value * value }
            if vNorm > 0 {
                r.reflect(v, vNorm: vNorm, fromRow: k, fromColumn: k)
                var s = 0.0
                for i in k..<m { s += v[i - k] * y[i] }
                let f = 2 * s / vNorm
                for i in k..<m { y[i] -= f * v[i - k] }
            }
        }
        return backSubstitute(r, y, tolerance: tolerance)
    }

    static func largestColumnNorm(_ a: DenseMatrix) -> Double {
        var scale = 0.0
        for j in 0..<a.columns {
            var s = 0.0
            for i in 0..<a.rows { s += a[i, j] * a[i, j] }
            scale = max(scale, s.squareRoot())
        }
        return scale
    }

    /// Solves R x = y for the upper triangle of `r`'s first `r.columns` rows, or `nil` on a
    /// pivot at or below `tolerance`.
    static func backSubstitute(_ r: DenseMatrix, _ y: [Double], tolerance: Double) -> [Double]? {
        let n = r.columns
        var x = Array(repeating: 0.0, count: n)
        for k in stride(from: n - 1, through: 0, by: -1) {
            var s = y[k]
            for j in (k + 1)..<n { s -= r[k, j] * x[j] }
            guard abs(r[k, k]) > tolerance else { return nil }
            x[k] = s / r[k, k]
        }
        return x
    }
}
