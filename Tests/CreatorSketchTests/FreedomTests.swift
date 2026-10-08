import CreatorGeometry
import Testing
@testable import CreatorSketch

/// Degrees of freedom and per-entity freedom from the rank-revealing QR (spec §4, §10).
struct FreedomTests {
    @Test func unconstrainedGeometryCountsEveryUnknown() {
        var sketch = Sketch()
        let point = sketch.addPoint(.zero)
        let line = sketch.addLine(Vector2(1, 1), Vector2(5, 1))
        let circle = sketch.addCircle(center: Vector2(9, 9), radius: 2)
        let solution = SketchSolver.solve(sketch)
        // 2 (point) + 4 (line) + 2 + 1 (circle centre and radius).
        #expect(solution.status == .underConstrained(dof: 9))
        #expect(solution.freedom[point] == .free)
        #expect(solution.freedom[line] == .free)
        #expect(solution.freedom[circle] == .free)
    }

    @Test func anchoredHorizontalLineHasOneFreedomAtItsEnd() {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(10, 1))
        let (start, end) = sketch.ends(line)
        sketch.add(.fix(start, at: .zero))
        sketch.add(.horizontal(line))
        let solution = SketchSolver.solve(sketch)
        #expect(solution.status == .underConstrained(dof: 1))
        #expect(solution.degreesOfFreedom == 1)
        #expect(solution.freedom[start] == .fixed)
        #expect(solution.freedom[end] == .free)
        #expect(solution.freedom[line] == .free)
    }

    @Test func rectangleWithoutItsHeightLeavesOnlyTheTopFree() {
        var rectangle = ConstrainedRectangle()
        rectangle.sketch.dimensions[rectangle.height] = nil
        let solution = SketchSolver.solve(rectangle.sketch)
        #expect(solution.status == .underConstrained(dof: 1))
        let (bottom, right, top, left) = (rectangle.lines[0], rectangle.lines[1], rectangle.lines[2], rectangle.lines[3])
        #expect(solution.freedom[bottom] == .fixed)
        #expect(solution.freedom[rectangle.sketch.ends(bottom).0] == .fixed)
        #expect(solution.freedom[rectangle.sketch.ends(bottom).1] == .fixed)
        #expect(solution.freedom[top] == .free)
        #expect(solution.freedom[right] == .free)
        #expect(solution.freedom[left] == .free)
    }

    @Test func pinnedLineWithALengthCanStillRotate() {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(3, 4))
        let (start, end) = sketch.ends(line)
        sketch.add(.fix(start, at: .zero))
        sketch.addDimension(.length(line), value: 5)
        let solution = SketchSolver.solve(sketch)
        #expect(solution.status == .underConstrained(dof: 1))
        #expect(solution.freedom[start] == .fixed)
        #expect(solution.freedom[end] == .free)
    }

    @Test func fixedCentreAndRadiusFixTheCircle() {
        var sketch = Sketch()
        let center = sketch.addPoint(Vector2(1, 1))
        let circle = sketch.addCircle(center: center, radius: 3)
        sketch.add(.fix(center, at: Vector2(1, 1)))
        sketch.addDimension(.diameter(circle), value: 8)
        let solution = SketchSolver.solve(sketch)
        #expect(solution.status == .solved)
        #expect(solution.freedom[circle] == .fixed)
    }

    @Test func projectedGeometryIsAlwaysFixed() {
        var sketch = Sketch()
        let edge = sketch.add(SketchEntity(.projected(ProjectionSource(reference: "e", curve: .line(.zero, Vector2(10, 0))))))
        let point = sketch.addPoint(Vector2(3, 2))
        sketch.add(.pointOn(point: point, curve: edge))
        let solution = SketchSolver.solve(sketch)
        #expect(solution.status == .underConstrained(dof: 1))
        #expect(solution.freedom[edge] == .fixed)
        #expect(solution.freedom[point] == .free)
        #expect(isClose(solution.points[point]?.y ?? 1, 0))
    }

    @Test func mirroredArcIsNotRedundantThoughItsRadiiAreImplied() {
        // All three arc points fixed: the implicit equal-radius row is implied, not redundant.
        var sketch = Sketch()
        let points = [Vector2(0, 0), Vector2(5, 0), Vector2(0, 5)].map { position in
            let point = sketch.addPoint(position)
            sketch.add(.fix(point, at: position))
            return point
        }
        sketch.addArc(center: points[0], start: points[1], end: points[2])
        #expect(SketchSolver.solve(sketch).status == .solved)
    }

    /// Rows that hold whatever the geometry is (concentric circles that already share a centre,
    /// horizontal on a projected edge that is horizontal) are neither redundancy nor conflict.
    @Test func constraintsThatAlwaysHoldAreNotRedundant() {
        var sketch = Sketch()
        let center = sketch.addPoint(.zero)
        sketch.add(.fix(center, at: .zero))
        let inner = sketch.addCircle(center: center, radius: 2)
        let outer = sketch.addCircle(center: center, radius: 3)
        sketch.addDimension(.radius(inner), value: 2)
        sketch.addDimension(.radius(outer), value: 3)
        let edge = sketch.add(SketchEntity(.projected(ProjectionSource(reference: "e", curve: .line(.zero, Vector2(10, 0))))))
        sketch.add(.concentric(inner, outer))
        sketch.add(.horizontal(edge))
        #expect(SketchSolver.solve(sketch).status == .solved)
    }
}
