/// Levenberg–Marquardt with a dense QR solve of the damped system (spec §4). Deterministic: no
/// randomness, fixed iteration order, and the same input gives bit-identical output. A start on
/// a stationary point (an unmet row with no gradient) is first nudged off it
/// (`ComponentSystem.unstuck`); that covers every solve, drag phase and conflict-search trial.
enum LevenbergMarquardt {
    /// Stop when every residual is at most this (mm).
    static let residualTolerance = 1e-9
    /// Stop when a step is at most this long.
    static let stepTolerance = 1e-12
    static let iterationLimit = 200
    /// Extra steps after converging. Stopping at 1e-9 leaves coincident points up to ~1e-9 mm
    /// apart, the same as the regions' merge tolerance; one or two more (quadratically
    /// converging) steps bring them to ~1e-14, so solved loops always close.
    static let polishSteps = 2
    /// Polishing stops (or never starts) once every residual is at most this, so re-solving an
    /// already solved sketch returns its warm start bit for bit and never creeps.
    static let polishedTolerance = 1e-12

    struct Outcome: Sendable {
        var x: [Double]
        var maxResidual: Double
        var iterations: Int
    }

    /// Minimises the sum of squared residuals from `start`. `iterationLimit` caps the iterations;
    /// with `stallFraction`, an accepted step that lowers the cost by less than that fraction of
    /// it ends the solve early (used by drag mode's pull, which only needs to get close).
    static func minimize(_ system: ComponentSystem, from start: [Double], iterationLimit: Int = iterationLimit,
                         stallFraction: Double? = nil) -> Outcome {
        var x = system.unstuck(start, tolerance: residualTolerance)
        var (r, jacobian) = system.evaluate(x)
        var iterations = 0
        guard system.columnCount > 0, !r.isEmpty else {
            return Outcome(x: x, maxResidual: maxAbs(r), iterations: 0)
        }
        let n = system.columnCount
        var mu = 1e-3 * max(1e-12, maxDiagonalOfNormalMatrix(jacobian))
        var nu = 2.0
        while iterations < iterationLimit, maxAbs(r) > residualTolerance {
            iterations += 1
            // Solve [J; √μ I] δ = [−r; 0].
            let m = jacobian.rows
            var augmented = DenseMatrix(rows: m + n, columns: n)
            for i in 0..<m {
                for j in 0..<n { augmented[i, j] = jacobian[i, j] }
            }
            let damping = mu.squareRoot()
            for j in 0..<n { augmented[m + j, j] = damping }
            let rhs = r.map { -$0 } + Array(repeating: 0, count: n)
            guard let step = HouseholderQR.leastSquares(augmented, rhs) else { break }
            let stepLength = step.reduce(0) { $0 + $1 * $1 }.squareRoot()
            if stepLength <= stepTolerance { break }
            let candidate = zip(x, step).map(+)
            let candidateResiduals = system.residuals(candidate)
            let gradient = transposeTimes(jacobian, r)
            let currentCost = 0.5 * sumOfSquares(r)
            let candidateCost = 0.5 * sumOfSquares(candidateResiduals)
            var predicted = 0.0
            for j in 0..<n { predicted += step[j] * (mu * step[j] - gradient[j]) }
            predicted *= 0.5
            let rho = predicted > 0 ? (currentCost - candidateCost) / predicted : -1
            if rho > 0, candidateCost.isFinite {
                x = candidate
                (r, jacobian) = system.evaluate(x)
                let factor = 2 * rho - 1
                mu *= max(1.0 / 3.0, 1 - factor * factor * factor)
                nu = 2
                if let stallFraction, currentCost - candidateCost < stallFraction * currentCost { break }
            } else {
                mu *= nu
                nu *= 2
            }
        }
        if maxAbs(r) <= residualTolerance {
            polish(system, &x, &r, &jacobian)
        }
        return Outcome(x: x, maxResidual: maxAbs(r), iterations: iterations)
    }

    /// Lightly damped steps from a converged solution, each kept only if it lowers the residual.
    static func polish(_ system: ComponentSystem, _ x: inout [Double], _ r: inout [Double], _ jacobian: inout DenseMatrix) {
        let n = system.columnCount
        for _ in 0..<polishSteps where maxAbs(r) > polishedTolerance {
            let m = jacobian.rows
            var augmented = DenseMatrix(rows: m + n, columns: n)
            for i in 0..<m {
                for j in 0..<n { augmented[i, j] = jacobian[i, j] }
            }
            for j in 0..<n { augmented[m + j, j] = 1e-9 }
            let rhs = r.map { -$0 } + Array(repeating: 0, count: n)
            guard let step = HouseholderQR.leastSquares(augmented, rhs) else { return }
            let candidate = zip(x, step).map(+)
            let candidateResiduals = system.residuals(candidate)
            guard sumOfSquares(candidateResiduals) < sumOfSquares(r) else { return }
            x = candidate
            (r, jacobian) = system.evaluate(x)
        }
    }

    static func maxAbs(_ values: [Double]) -> Double {
        values.reduce(0) { max($0, abs($1)) }
    }

    static func sumOfSquares(_ values: [Double]) -> Double {
        values.reduce(0) { $0 + $1 * $1 }
    }

    static func transposeTimes(_ a: DenseMatrix, _ v: [Double]) -> [Double] {
        var result = Array(repeating: 0.0, count: a.columns)
        for i in 0..<a.rows {
            for j in 0..<a.columns { result[j] += a[i, j] * v[i] }
        }
        return result
    }

    static func maxDiagonalOfNormalMatrix(_ a: DenseMatrix) -> Double {
        var best = 0.0
        for j in 0..<a.columns {
            var s = 0.0
            for i in 0..<a.rows { s += a[i, j] * a[i, j] }
            best = max(best, s)
        }
        return best
    }
}
