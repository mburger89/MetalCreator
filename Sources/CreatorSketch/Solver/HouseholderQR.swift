/// Least squares by Householder QR, used for every Levenberg–Marquardt step.
enum HouseholderQR {
    /// Solves min ‖A x − b‖ for `a` with at least as many rows as columns. Returns `nil` when
    /// `a` is rank deficient (a zero pivot), which the damped LM system never is.
    static func leastSquares(_ a: DenseMatrix, _ b: [Double]) -> [Double]? {
        var r = a
        var y = b
        let (m, n) = (a.rows, a.columns)
        guard m >= n, b.count == m else { return nil }
        for k in 0..<n {
            var norm = 0.0
            for i in k..<m { norm += r[i, k] * r[i, k] }
            norm = norm.squareRoot()
            guard norm > 0 else { return nil }
            let alpha = r[k, k] > 0 ? -norm : norm
            var v = Array(repeating: 0.0, count: m - k)
            for i in k..<m { v[i - k] = r[i, k] }
            v[0] -= alpha
            var vNorm = 0.0
            for value in v { vNorm += value * value }
            if vNorm > 0 {
                for j in k..<n {
                    var s = 0.0
                    for i in k..<m { s += v[i - k] * r[i, j] }
                    let f = 2 * s / vNorm
                    for i in k..<m { r[i, j] -= f * v[i - k] }
                }
                var s = 0.0
                for i in k..<m { s += v[i - k] * y[i] }
                let f = 2 * s / vNorm
                for i in k..<m { y[i] -= f * v[i - k] }
            }
        }
        var x = Array(repeating: 0.0, count: n)
        for k in stride(from: n - 1, through: 0, by: -1) {
            var s = y[k]
            for j in (k + 1)..<n { s -= r[k, j] * x[j] }
            guard r[k, k] != 0 else { return nil }
            x[k] = s / r[k, k]
        }
        return x
    }
}
