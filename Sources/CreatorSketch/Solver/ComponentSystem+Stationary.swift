extension ComponentSystem {
    /// How far (mm) `unstuck` moves one unknown.
    static let stationaryNudge = 1e-6

    /// The start moved off any stationary point: a row that is not met but has no gradient at all
    /// (a line drawn with both ends in one place, so it has no direction) gives LM nothing to
    /// follow, and it would stall there and report a false conflict. Each such term's first
    /// unknown moves by `stationaryNudge`, deterministically. A start without such rows comes back
    /// unchanged, so re-solving a solved sketch stays bit-identical.
    func unstuck(_ local: [Double], tolerance: Double) -> [Double] {
        let (residuals, jacobian) = evaluate(local)
        var x = local
        var moved = Set<Int>()
        for (term, range) in zip(terms, rowRanges) {
            let isStationary = range.contains { row in
                abs(residuals[row]) > tolerance && (0..<columnCount).allSatisfy { jacobian[row, $0] == 0 }
            }
            guard isStationary, let column = term.equation.columns.lazy.compactMap(localColumn).first,
                  moved.insert(column).inserted else { continue }
            x[column] += Self.stationaryNudge
        }
        return x
    }
}
