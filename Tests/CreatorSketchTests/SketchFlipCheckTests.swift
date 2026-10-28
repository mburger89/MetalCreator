import CreatorGeometry
import Foundation
import Testing
@testable import CreatorSketch

/// Flip detection (spec §7): a solve that turns a corner or an arc over.
struct SketchFlipCheckTests {
    private func mirrored(_ solution: SketchSolution) -> SketchSolution {
        var copy = solution
        copy.points = solution.points.mapValues { Vector2($0.x, -$0.y) }
        return copy
    }

    @Test func theSameSolveIsNotAFlip() {
        let triangle = SolverBehaviourTests.Triangle(base: 40)
        let solution = SketchSolver.solve(triangle.sketch)
        #expect(!SketchFlipCheck.isFlipped(solution, solution, in: triangle.sketch))
    }

    @Test func aMirroredTriangleIsAFlip() {
        let triangle = SolverBehaviourTests.Triangle(base: 40)
        let before = SketchSolver.solve(triangle.sketch)
        #expect(SketchFlipCheck.isFlipped(before, mirrored(before), in: triangle.sketch))
    }

    @Test func sweepingTheBaseFlipsNothing() {
        var triangle = SolverBehaviourTests.Triangle(base: 10)
        var previous = SketchSolver.solve(triangle.sketch)
        triangle.sketch.remember(previous)
        for value in stride(from: 11.0, through: 100, by: 1) {
            triangle.sketch.dimensions[triangle.base]?.value = value
            let next = SketchSolver.solve(triangle.sketch)
            #expect(!SketchFlipCheck.isFlipped(previous, next, in: triangle.sketch), "base \(value)")
            triangle.sketch.remember(next)
            previous = next
        }
    }

    @Test func anInvertedArcIsAFlip() throws {
        let slot = ClassicSketchTests.Slot()
        let solved = SketchSolver.solve(slot.sketch)
        let (center, start, end) = slot.sketch.arcPoints(slot.right)
        // The slot's caps are exact semicircles, which have no side; take a quarter turn of the right cap instead.
        var before = solved
        let middle = try #require(solved.points[center])
        before.points[start] = middle + Vector2(0, -5)
        before.points[end] = middle + Vector2(5, 0)
        var after = before
        after.points[start] = before.points[end]
        after.points[end] = before.points[start]
        #expect(SketchFlipCheck.isFlipped(before, after, in: slot.sketch))
        #expect(!SketchFlipCheck.isFlipped(before, before, in: slot.sketch))
    }

    @Test func nearlyStraightCornersAreNotFlips() {
        var sketch = Sketch()
        let middle = sketch.addPoint(.zero)
        let left = sketch.addPoint(Vector2(-10, 0))
        let right = sketch.addPoint(Vector2(10, 0))
        _ = sketch.addLine(from: left, to: middle)
        _ = sketch.addLine(from: middle, to: right)
        func solution(opening degrees: Double) -> SketchSolution {
            let tilt = (180 - degrees) / 2 * .pi / 180
            var solved = SketchSolver.solve(sketch)
            solved.points = [
                middle: .zero,
                left: Vector2(-10 * cos(tilt), 10 * sin(tilt)),
                right: Vector2(10 * cos(tilt), 10 * sin(tilt)),
            ]
            return solved
        }
        #expect(!SketchFlipCheck.isFlipped(solution(opening: 179.5), solution(opening: 180.5), in: sketch))
        // A clear turn the other way is still caught.
        #expect(SketchFlipCheck.isFlipped(solution(opening: 120), solution(opening: 240), in: sketch))
    }

    @Test func anUnusableAfterIsNotAFlip() {
        let triangle = SolverBehaviourTests.Triangle(base: 40)
        let before = SketchSolver.solve(triangle.sketch)
        var after = mirrored(before)
        after.status = .failed(reason: "no")
        #expect(!SketchFlipCheck.isFlipped(before, after, in: triangle.sketch))
    }
}
