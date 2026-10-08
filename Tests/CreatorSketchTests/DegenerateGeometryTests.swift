import CreatorGeometry
import Foundation
import Testing
@testable import CreatorSketch

/// A solve that meets its constraints only with a collapsed or inside-out curve is not usable
/// geometry (final review): drags fall back, and plain solves say what went wrong.
struct DegenerateGeometryTests {
    /// A circle tangent to a fixed line along the x axis, centred above it.
    struct TangentCircle {
        var sketch = Sketch()
        let circle: SketchEntityID
        let center: SketchEntityID

        init() {
            let a = sketch.addPoint(.zero)
            sketch.add(.fix(a, at: .zero))
            let b = sketch.addPoint(Vector2(100, 0))
            sketch.add(.fix(b, at: Vector2(100, 0)))
            let line = sketch.addLine(from: a, to: b)
            center = sketch.addPoint(Vector2(50, 10))
            circle = sketch.addCircle(center: center, radius: 10)
            sketch.add(.tangent(line, circle))
        }
    }

    @Test func draggingATangentCircleAcrossItsLineNeverTurnsItsRadiusNegative() throws {
        let fixture = TangentCircle()
        let solution = SketchSolver.solve(fixture.sketch, dragging: [fixture.center: Vector2(50, -20)])
        #expect(solution.status.isUsable, "status \(solution.status)")
        let radius = try #require(solution.radii[fixture.circle])
        #expect(radius > 1)
        let center = try #require(solution.points[fixture.center])
        #expect(isClose(radius, center.y, tolerance: 1e-6))
    }

    @Test func aPointOnACircleDrawnAtItsCentreDoesNotCollapseIt() throws {
        var sketch = Sketch()
        let center = sketch.addPoint(Vector2(5, 5))
        let circle = sketch.addCircle(center: center, radius: 4)
        let point = sketch.addPoint(Vector2(5, 5))
        sketch.add(.pointOn(point: point, curve: circle))
        let solution = SketchSolver.solve(sketch)
        #expect(solution.status.isUsable, "status \(solution.status)")
        let radius = try #require(solution.radii[circle])
        #expect(radius > 1)
        let distance = (try #require(solution.points[point]) - (try #require(solution.points[center]))).length
        #expect(isClose(distance, radius))
    }

    /// Tangent to a line its centre is fixed on: only a zero radius meets it.
    @Test func aCircleThatCanOnlyShrinkToNothingIsAnError() throws {
        var fixture = TangentCircle()
        fixture.sketch.add(.fix(fixture.center, at: Vector2(50, 0)))
        let solution = SketchSolver.solve(fixture.sketch)
        #expect(solution.status == .failed(reason: "Circle 1 would shrink to nothing."))
        // The last good geometry stays.
        #expect(solution.radii[fixture.circle] == 10)
    }
}
