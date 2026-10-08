import CreatorGeometry
import Foundation
import Testing
@testable import CreatorSketch

/// Warm start, determinism, branch stability and drag mode (spec §4 guarantees, §10).
struct SolverBehaviourTests {
    /// An isosceles triangle on a horizontal base fixed at the origin: base `d1`, sides 60.
    struct Triangle {
        var sketch = Sketch()
        let base: DimensionID
        let a: SketchEntityID
        let b: SketchEntityID
        let c: SketchEntityID

        init(base value: Double, apexAbove: Bool = true) {
            let lines = addPolygon(&sketch, [.zero, Vector2(value, 0), Vector2(value / 2, apexAbove ? 50 : -50)])
            (a, b) = sketch.ends(lines[0])
            c = sketch.ends(lines[1]).1
            sketch.add(.fix(a, at: .zero))
            sketch.add(.horizontal(lines[0]))
            base = sketch.addDimension(.length(lines[0]), value: value)
            sketch.addDimension(.length(lines[1]), value: 60)
            sketch.addDimension(.length(lines[2]), value: 60)
        }

        /// Positive when C is counter-clockwise of A → B (above the base).
        func orientation(_ solution: SketchSolution) -> Double {
            guard let pa = solution.points[a], let pb = solution.points[b], let pc = solution.points[c] else { return 0 }
            return SketchMath.cross(pb - pa, pc - pa)
        }
    }

    @Test func warmStartChoosesTheBranchOverTheDrawing() {
        var triangle = Triangle(base: 40)
        #expect(triangle.orientation(SketchSolver.solve(triangle.sketch)) > 0)
        // The last good solve had the apex below; the warm start wins over the drawn position.
        triangle.sketch.solved[triangle.c] = .point(Vector2(20, -50))
        #expect(triangle.orientation(SketchSolver.solve(triangle.sketch)) < 0)
    }

    @Test func twoSolvesAreBitIdentical() throws {
        let slot = ClassicSketchTests.Slot(length: 33, radius: 4)
        let first = SketchSolver.solve(slot.sketch)
        let second = SketchSolver.solve(slot.sketch)
        #expect(first == second)
        // Decoding rebuilds every dictionary; the result still doesn't change by a bit.
        let copy = try JSONDecoder().decode(Sketch.self, from: try JSONEncoder().encode(slot.sketch))
        #expect(SketchSolver.solve(copy) == first)
    }

    @Test func sweepingTheBaseNeverReflectsTheTriangle() {
        var triangle = Triangle(base: 10)
        for value in stride(from: 10.0, through: 100, by: 1) {
            triangle.sketch.dimensions[triangle.base]?.value = value
            let solution = SketchSolver.solve(triangle.sketch)
            #expect(solution.status == .solved, "base \(value)")
            #expect(triangle.orientation(solution) > 0, "base \(value)")
            triangle.sketch.remember(solution)
        }
    }

    @Test func sweepingTheSlotLengthNeverInvertsAnArc() throws {
        var slot = ClassicSketchTests.Slot(length: 10)
        let (rightCenter, rightStart, _) = slot.sketch.arcPoints(slot.right)
        for value in stride(from: 10.0, through: 100, by: 1) {
            slot.sketch.dimensions[slot.length]?.value = value
            let solution = SketchSolver.solve(slot.sketch)
            #expect(solution.status == .solved, "length \(value)")
            // The right cap runs counter-clockwise from its bottom (start) point, so its start
            // stays below its centre and the cap bulges to the right.
            let center = try #require(solution.points[rightCenter])
            let start = try #require(solution.points[rightStart])
            #expect(isClose(center.x, value), "length \(value)")
            #expect(start.y < center.y, "length \(value)")
            slot.sketch.remember(solution)
        }
    }

    @Test func draggingAFreeEndSwingsItAroundItsLength() throws {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(10, 0))
        let (start, end) = sketch.ends(line)
        sketch.add(.fix(start, at: .zero))
        sketch.addDimension(.length(line), value: 10)
        let solution = SketchSolver.solve(sketch, dragging: [end: Vector2(0, 20)])
        #expect(solution.status.isUsable)
        let moved = try #require(solution.points[end])
        #expect(isClose(moved.length, 10))
        #expect(isNear(moved, Vector2(0, 10)))
    }

    @Test func draggingAFixedPointLeavesItWhereItIs() throws {
        var sketch = Sketch()
        let point = sketch.addPoint(Vector2(2, 2))
        sketch.add(.fix(point, at: Vector2(2, 2)))
        let solution = SketchSolver.solve(sketch, dragging: [point: Vector2(50, 50)])
        #expect(solution.status == .solved)
        #expect(isClose(try #require(solution.points[point]), Vector2(2, 2)))
    }

    @Test func draggingARectangleCornerKeepsItsConstraints() throws {
        var rectangle = ConstrainedRectangle()
        rectangle.sketch.dimensions = [:]
        let corner = rectangle.sketch.ends(rectangle.lines[2]).0
        let solution = SketchSolver.solve(rectangle.sketch, dragging: [corner: Vector2(80, 55)])
        #expect(solution.status.isUsable)
        #expect(isNear(try #require(solution.points[corner]), Vector2(80, 55)))
        let corners = (0..<4).compactMap { rectangle.corner($0, in: solution) }
        #expect(corners.count == 4)
        #expect(isClose(corners[0].y, corners[1].y))
        #expect(isClose(corners[1].x, corners[2].x))
        #expect(isClose(corners[2].y, corners[3].y))
        #expect(isClose(corners[3].x, corners[0].x))
        #expect(isClose(corners[0], .zero))
    }

    @Test func draggingAnUnconstrainedPointPutsItOnTheTarget() {
        var sketch = Sketch()
        let point = sketch.addPoint(.zero)
        let solution = SketchSolver.solve(sketch, dragging: [point: Vector2(7, -3)])
        #expect(isClose(solution.points[point] ?? .zero, Vector2(7, -3)))
    }
}
