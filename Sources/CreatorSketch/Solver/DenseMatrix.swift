/// A row-major dense matrix. Sketch components have tens to a few hundred unknowns, so dense
/// storage is simpler and fast enough (spec §4: dense QR).
struct DenseMatrix: Hashable, Sendable {
    let rows: Int
    let columns: Int
    var storage: [Double]

    init(rows: Int, columns: Int) {
        self.rows = rows
        self.columns = columns
        storage = Array(repeating: 0, count: rows * columns)
    }

    /// A matrix from row arrays, which must all have `columns` entries.
    init(_ rowValues: [[Double]], columns: Int) {
        self.init(rows: rowValues.count, columns: columns)
        for (i, row) in rowValues.enumerated() {
            for (j, value) in row.enumerated() { self[i, j] = value }
        }
    }

    subscript(row: Int, column: Int) -> Double {
        get { storage[row * columns + column] }
        set { storage[row * columns + column] = newValue }
    }

    var transposed: DenseMatrix {
        var result = DenseMatrix(rows: columns, columns: rows)
        for i in 0..<rows {
            for j in 0..<columns { result[j, i] = self[i, j] }
        }
        return result
    }

    /// The rows at `indices`, in that order.
    func selectingRows(_ indices: [Int]) -> DenseMatrix {
        var result = DenseMatrix(rows: indices.count, columns: columns)
        for (target, source) in indices.enumerated() {
            for j in 0..<columns { result[target, j] = self[source, j] }
        }
        return result
    }

    /// Applies the Householder reflector I − 2 v vᵀ / ‖v‖² (v running over rows `start...`) to
    /// columns `firstColumn...`. Walks the row-major storage row by row, so it stays in cache;
    /// each column's dot product still sums over rows in ascending order, exactly as a
    /// column-by-column loop would.
    mutating func reflect(_ v: [Double], vNorm: Double, fromRow start: Int, fromColumn firstColumn: Int) {
        let width = columns - firstColumn
        guard width > 0, vNorm > 0 else { return }
        var factors = Array(repeating: 0.0, count: width)
        for i in start..<rows {
            let vi = v[i - start]
            let base = i * columns + firstColumn
            for j in 0..<width { factors[j] += vi * storage[base + j] }
        }
        for j in 0..<width { factors[j] = 2 * factors[j] / vNorm }
        for i in start..<rows {
            let vi = v[i - start]
            let base = i * columns + firstColumn
            for j in 0..<width { storage[base + j] -= factors[j] * vi }
        }
    }
}
