/// Householder QR with column pivoting (spec §4: rank-revealing QR). Gives the numerical rank and
/// an orthonormal basis of the column space.
struct RankRevealingQR {
    /// Pivots whose remaining column norm is at or below this fraction of max(1, the first
    /// pivot's norm) count as zero.
    static let relativeTolerance = 1e-8

    let rank: Int
    /// `rows × rank`: orthonormal columns spanning the matrix's column space.
    let rangeBasis: DenseMatrix

    init(_ a: DenseMatrix) {
        let (m, n) = (a.rows, a.columns)
        var r = a
        var reflectors: [(start: Int, v: [Double], vNorm: Double)] = []
        var threshold = 0.0
        var rank = 0
        for k in 0..<min(m, n) {
            let (best, bestNorm) = Self.pivot(r, from: k)
            let norm = bestNorm.squareRoot()
            if k == 0 { threshold = Self.relativeTolerance * max(1, norm) }
            if norm <= threshold { break }
            if best != k {
                for i in 0..<m {
                    let t = r[i, k]
                    r[i, k] = r[i, best]
                    r[i, best] = t
                }
            }
            let alpha = r[k, k] > 0 ? -norm : norm
            var v = Array(repeating: 0.0, count: m - k)
            for i in k..<m { v[i - k] = r[i, k] }
            v[0] -= alpha
            var vNorm = 0.0
            for value in v { vNorm += value * value }
            r.reflect(v, vNorm: vNorm, fromRow: k, fromColumn: k)
            reflectors.append((k, v, vNorm))
            rank += 1
        }
        self.rank = rank
        rangeBasis = Self.basis(rows: m, rank: rank, reflectors: reflectors)
    }

    /// The remaining column with the largest squared norm below row `k`, and that norm (first
    /// wins on ties).
    static func pivot(_ r: DenseMatrix, from k: Int) -> (column: Int, squaredNorm: Double) {
        var norms = Array(repeating: 0.0, count: r.columns - k)
        for i in k..<r.rows {
            for j in k..<r.columns { norms[j - k] += r[i, j] * r[i, j] }
        }
        var best = k
        var bestNorm = -1.0
        for j in k..<r.columns where norms[j - k] > bestNorm {
            bestNorm = norms[j - k]
            best = j
        }
        return (best, bestNorm)
    }

    /// Q's first `rank` columns: the reflectors applied in reverse to the unit vectors.
    static func basis(rows m: Int, rank: Int, reflectors: [(start: Int, v: [Double], vNorm: Double)]) -> DenseMatrix {
        var basis = DenseMatrix(rows: m, columns: rank)
        for column in 0..<rank {
            var e = Array(repeating: 0.0, count: m)
            e[column] = 1
            for reflector in reflectors.reversed() where reflector.vNorm > 0 {
                var s = 0.0
                for i in reflector.start..<m { s += reflector.v[i - reflector.start] * e[i] }
                let f = 2 * s / reflector.vNorm
                for i in reflector.start..<m { e[i] -= f * reflector.v[i - reflector.start] }
            }
            for i in 0..<m { basis[i, column] = e[i] }
        }
        return basis
    }

    /// The squared length of unit vector `e_row`'s component outside the column space.
    func outsideSquaredNorm(ofUnitVector row: Int) -> Double {
        var inside = 0.0
        for k in 0..<rank { inside += rangeBasis[row, k] * rangeBasis[row, k] }
        return max(0, 1 - inside)
    }
}
