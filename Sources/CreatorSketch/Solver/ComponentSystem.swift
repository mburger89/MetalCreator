/// The residual system of one connected component. Equations use global unknown columns; the
/// component varies only `columns` (sorted), and every other unknown stays at `base`.
struct ComponentSystem: Sendable {
    var terms: [SolverTerm]
    /// The global columns this component solves for, ascending.
    var columns: [Int]
    /// The full global unknown vector the component's values are written into.
    var base: [Double]
    /// Global column → local index, −1 for columns outside the component.
    private var localIndex: [Int]

    init(terms: [SolverTerm], columns: [Int], base: [Double]) {
        self.terms = terms
        self.columns = columns
        self.base = base
        var localIndex = Array(repeating: -1, count: base.count)
        for (local, global) in columns.enumerated() { localIndex[global] = local }
        self.localIndex = localIndex
    }

    var columnCount: Int { columns.count }

    /// The component's unknowns read from a global vector.
    func local(_ global: [Double]) -> [Double] { columns.map { global[$0] } }

    /// `base` with the component's unknowns replaced by `local`.
    func global(_ local: [Double]) -> [Double] {
        var x = base
        for (index, column) in columns.enumerated() { x[column] = local[index] }
        return x
    }

    func residuals(_ local: [Double]) -> [Double] {
        let x = global(local)
        return terms.flatMap { $0.equation.rows(x).map(\.value) }
    }

    /// Residuals and the dense analytic Jacobian over local columns (rows in term order).
    func evaluate(_ local: [Double]) -> (residuals: [Double], jacobian: DenseMatrix) {
        let x = global(local)
        let rows = terms.flatMap { $0.equation.rows(x) }
        var jacobian = DenseMatrix(rows: rows.count, columns: columnCount)
        for (i, row) in rows.enumerated() {
            for entry in row.entries where localIndex[entry.column] >= 0 {
                jacobian[i, localIndex[entry.column]] += entry.value
            }
        }
        return (rows.map(\.value), jacobian)
    }

    /// The row indices of each term, in term order.
    var rowRanges: [Range<Int>] {
        var start = 0
        return terms.map { term in
            defer { start += term.equation.rowCount }
            return start..<(start + term.equation.rowCount)
        }
    }

    /// The same component with only the terms that pass `isIncluded`.
    func filtered(_ isIncluded: (SolverTerm) -> Bool) -> ComponentSystem {
        ComponentSystem(terms: terms.filter(isIncluded), columns: columns, base: base)
    }

    /// The same component with extra terms appended.
    func adding(_ extra: [SolverTerm]) -> ComponentSystem {
        ComponentSystem(terms: terms + extra, columns: columns, base: base)
    }
}
