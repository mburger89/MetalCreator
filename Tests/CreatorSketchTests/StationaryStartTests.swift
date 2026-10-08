import CreatorGeometry
import Foundation
import Testing
@testable import CreatorSketch

/// Exact drawings (snapped, as the editor makes them) can start a solve where a residual is
/// furthest from met. Each must still solve, not stall into a false conflict (final review).
struct StationaryStartTests {
    @Test func horizontalOnAnExactlyVerticalLineSolves() throws {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(0, 10))
        sketch.add(.horizontal(line))
        let solution = SketchSolver.solve(sketch)
        try #require(solution.status.isUsable, "status \(solution.status) \(solution.conflictMessages)")
        let (start, end) = sketch.ends(line)
        let d = try #require(solution.points[end]) - (try #require(solution.points[start]))
        #expect(abs(d.y) <= 1e-9)
        #expect(d.length > 1)
    }

    @Test func perpendicularOnExactlyParallelLinesSolves() throws {
        var sketch = Sketch()
        let first = sketch.addLine(.zero, Vector2(10, 0))
        let second = sketch.addLine(Vector2(0, 5), Vector2(10, 5))
        sketch.add(.perpendicular(first, second))
        let solution = SketchSolver.solve(sketch)
        try #require(solution.status.isUsable, "status \(solution.status) \(solution.conflictMessages)")
    }

    @Test func aDistanceBetweenCoincidentPointsSolves() throws {
        var sketch = Sketch()
        let p = sketch.addPoint(Vector2(3, 3))
        let q = sketch.addPoint(Vector2(3, 3))
        sketch.addDimension(.distance(p, q), value: 5)
        let solution = SketchSolver.solve(sketch)
        try #require(solution.status.isUsable, "status \(solution.status) \(solution.conflictMessages)")
        #expect(isClose((try #require(solution.points[p]) - (try #require(solution.points[q]))).length, 5))
    }

    /// A line drawn with both ends in one place has no direction yet; it gets one.
    @Test func horizontalOnALineDrawnAsAPointSolves() throws {
        var sketch = Sketch()
        let line = sketch.addLine(from: sketch.addPoint(Vector2(2, 2)), to: sketch.addPoint(Vector2(2, 2)))
        sketch.add(.horizontal(line))
        let solution = SketchSolver.solve(sketch)
        #expect(solution.status.isUsable, "status \(solution.status) \(solution.conflictMessages)")
    }

    /// The exactly drawn rectangle names the same conflict as the one drawn slightly off.
    @Test(arguments: [0, 0.7])
    func anExactRectangleNamesTheWholeConflict(drawnOffset: Double) {
        var rectangle = ConstrainedRectangle(drawnOffset: drawnOffset)
        rectangle.sketch.add(.vertical(rectangle.lines[0]))
        let solution = SketchSolver.solve(rectangle.sketch)
        #expect(solution.conflictMessages == ["Horizontal on Line 1 conflicts with Vertical on Line 1."])
    }

    /// An exactly drawn, fully constrained rectangle is still fully constrained.
    @Test func anExactRectangleSolvesInPlace() throws {
        let rectangle = ConstrainedRectangle(drawnOffset: 0)
        #expect(try requireSolvesInPlace(rectangle.sketch).status == .solved)
    }
}
