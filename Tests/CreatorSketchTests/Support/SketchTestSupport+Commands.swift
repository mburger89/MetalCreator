// Test fixture file: helpers for command tests (several helpers by design).
import CreatorGeometry
import Testing
@testable import CreatorSketch

/// Solves an edited sketch and requires a usable result that left every point where the command
/// put it (commands create geometry that already satisfies what they add).
@discardableResult
func requireSolvesInPlace(_ sketch: Sketch, sourceLocation: SourceLocation = #_sourceLocation) throws -> SketchSolution {
    let solution = SketchSolver.solve(sketch)
    try #require(solution.status.isUsable, "status \(solution.status)", sourceLocation: sourceLocation)
    for id in sketch.entityIDs {
        guard let before = sketch.position(of: id), let after = solution.points[id] else { continue }
        #expect(isClose(before, after, tolerance: 1e-6), "\(sketch.label(of: id)) moved", sourceLocation: sourceLocation)
    }
    return solution
}

extension Sketch {
    /// The constraints of the sketch, as a list, for membership checks.
    var constraintList: [SketchConstraint] { constraintIDs.compactMap { constraints[$0] } }
}
