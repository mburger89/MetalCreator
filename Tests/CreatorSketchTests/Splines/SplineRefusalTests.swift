import CreatorGeometry
import Foundation
import Testing
@testable import CreatorSketch

/// What the solver refuses about splines, in words.
struct SplineRefusalTests {
    typealias LineAndSpline = SplineSolverTests.LineAndSpline

    @Test func lineToArcCurvatureIsRefused() {
        var sketch = Sketch()
        let (arc, start, _) = SplineSolverTests.quarterArc(in: &sketch)
        let far = sketch.addPoint(Vector2(20, -5))
        let line = sketch.addLine(from: start, to: far)
        sketch.add(.curvature(line, arc))
        let solution = SketchSolver.solve(sketch)
        #expect(solution.status == .failed(reason: "A line and an arc can't meet with equal curvature."))
    }

    @Test func aConstraintOnAnInactiveHandleNamesIt() {
        var fixture = LineAndSpline()
        fixture.sketch.add(.tangent(fixture.line, fixture.spline))
        guard case .failed(let reason) = SketchSolver.solve(fixture.sketch).status else {
            Issue.record("expected a failure")
            return
        }
        #expect(reason.contains("tangent handle") && reason.contains("Spline 1"))
        var curvature = LineAndSpline()
        curvature.sketch.activateSplineHandle(curvature.spline, at: 0, .tangent)
        curvature.sketch.add(.curvature(curvature.line, curvature.spline))
        guard case .failed(let second) = SketchSolver.solve(curvature.sketch).status else {
            Issue.record("expected a failure")
            return
        }
        #expect(second.contains("curvature handle"))
    }

    @Test func curvatureNeedsASplineEndSharedWithTheOtherCurve() {
        var fixture = LineAndSpline()
        fixture.sketch.activateSplineHandle(fixture.spline, at: 0, .tangent)
        fixture.sketch.activateSplineHandle(fixture.spline, at: 0, .curvature)
        let apart = fixture.sketch.addLine(Vector2(30, 0), Vector2(40, 0))
        fixture.sketch.add(.curvature(apart, fixture.spline))
        guard case .failed(let reason) = SketchSolver.solve(fixture.sketch).status else {
            Issue.record("expected a failure")
            return
        }
        #expect(reason.contains("end at the same point"))
    }

    @Test func aSplineWithTheSameFitPointTwiceIsRefused() {
        var sketch = Sketch()
        let p = sketch.addPoint(.zero)
        sketch.addSpline(through: [p, p])
        guard case .failed(let reason) = SketchSolver.solve(sketch).status else {
            Issue.record("expected a failure")
            return
        }
        #expect(reason.contains("same fit point twice"))
    }

    @Test func pointOnASplineIsRefusedInWords() {
        var sketch = Sketch()
        let spline = sketch.addSpline([Vector2(0, 0), Vector2(4, 3)])
        let point = sketch.addPoint(Vector2(2, 1))
        sketch.add(.pointOn(point: point, curve: spline))
        #expect(SketchSolver.solve(sketch).status == .failed(reason: "Point on doesn't work on splines yet."))
    }
}
