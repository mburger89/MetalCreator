/// Solves one component, then analyses it: degrees of freedom and free unknowns from a
/// rank-revealing QR of the Jacobian, and minimal conflict sets when it can't be satisfied or
/// its constraints are redundant (spec §4).
enum ComponentSolver {
    /// A solve whose largest residual ends at or below this (mm) satisfies its constraints. LM
    /// stops at 1e-9 when it converges; a stalled solve at a least-squares minimum of an
    /// impossible sketch leaves residuals far larger than this.
    static let satisfiedTolerance = 1e-7
    /// An unknown whose unit vector has at least this squared length outside the Jacobian's row
    /// space can still move.
    static let freeTolerance = 1e-10

    struct Outcome: Sendable {
        /// Local unknown values: the solution, or the warm start when unsatisfied.
        var x: [Double]
        var isSatisfied: Bool
        /// Minimal conflicting sets, one per independent conflict; empty when the component is
        /// consistent and independent.
        var conflictSets: [[SketchConstraintRef]]
        var degreesOfFreedom: Int
        /// Global columns that can still move.
        var freeColumns: [Int]
        /// Why the solution was refused when it met every constraint only with degenerate
        /// geometry (`DegenerateGeometry`); the component then keeps its warm start.
        var degenerateReason: String? = nil
    }

    /// `degeneracy` reads a global unknown vector and names a collapsed or inverted curve, if any.
    static func solve(_ component: ComponentPartition.Component, base: [Double],
                      degeneracy: ([Double]) -> String? = { _ in nil }) -> Outcome {
        let full = ComponentSystem(terms: component.terms, columns: component.columns, base: base)
        let system = full.filtered { $0.role != .drag }
        let drags = full.terms.filter { $0.role == .drag }
        let start = system.local(base)
        var result: LevenbergMarquardt.Outcome?
        if !drags.isEmpty {
            // Drag mode (spec §4 step 4): pull towards the targets as soft rows, then restore every
            // hard constraint exactly from there, so geometry slides along its remaining freedom.
            // A result that only holds by collapsing or inverting a curve is dropped, and the
            // component solves as if not dragged.
            let pulled = LevenbergMarquardt.minimize(system.adding(drags), from: start)
            let projected = LevenbergMarquardt.minimize(system, from: pulled.x)
            if projected.maxResidual <= satisfiedTolerance, degeneracy(system.global(projected.x)) == nil {
                result = projected
            }
        }
        let solved = result ?? LevenbergMarquardt.minimize(system, from: start)
        var isSatisfied = solved.maxResidual <= satisfiedTolerance
        let degenerateReason = isSatisfied ? degeneracy(system.global(solved.x)) : nil
        if degenerateReason != nil { isSatisfied = false }
        let x = isSatisfied ? solved.x : start
        let analysis = analyse(system, at: x)
        var conflictSets: [[SketchConstraintRef]] = []
        if !isSatisfied, degenerateReason == nil {
            conflictSets = ConflictSearch.unsatisfiableSets(system, from: start, stalled: solved.x).sets
        } else if analysis.isRedundant {
            conflictSets = ConflictSearch.dependentSets(system, at: x)
        }
        return Outcome(x: x, isSatisfied: isSatisfied, conflictSets: conflictSets,
                       degreesOfFreedom: analysis.degreesOfFreedom, freeColumns: analysis.freeColumns,
                       degenerateReason: degenerateReason)
    }

    struct Analysis {
        var degreesOfFreedom: Int
        var freeColumns: [Int]
        var isRedundant: Bool
    }

    /// DOF = unknowns − rank(J). An unknown is free when its unit vector leaves the row space of J
    /// (the range of Jᵀ), that is, when it touches the null space. The constraints are redundant
    /// when the user rows alone are linearly dependent; implicit rows (an arc's equal radii) may
    /// be implied by user rows without counting as redundancy.
    static func analyse(_ system: ComponentSystem, at x: [Double]) -> Analysis {
        let n = system.columnCount
        let (_, jacobian) = system.evaluate(x)
        let qr = RankRevealingQR(jacobian.transposed)
        let free = (0..<n).filter { qr.outsideSquaredNorm(ofUnitVector: $0) > freeTolerance }.map { system.columns[$0] }
        let userRows = rows(of: system) { $0.userRef != nil }
        let userRank = RankRevealingQR(jacobian.selectingRows(userRows)).rank
        return Analysis(degreesOfFreedom: n - qr.rank, freeColumns: free, isRedundant: userRank < userRows.count)
    }

    /// Indices of the Jacobian rows whose terms pass `isIncluded`.
    static func rows(of system: ComponentSystem, where isIncluded: (SolverTerm) -> Bool) -> [Int] {
        zip(system.terms, system.rowRanges).flatMap { term, range in isIncluded(term) ? Array(range) : [] }
    }

    /// The user refs of a system, each once, in term order.
    static func refs(of system: ComponentSystem) -> [SketchConstraintRef] {
        var seen = Set<SketchConstraintRef>()
        return system.terms.compactMap(\.userRef).filter { seen.insert($0).inserted }
    }
}
