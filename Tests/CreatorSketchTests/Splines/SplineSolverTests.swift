import CreatorGeometry
import Foundation
import Testing
@testable import CreatorSketch

/// Splines in the solver: degrees of freedom, Tangent and Curvature at a spline end, the refusals and the conflicts.
struct SplineSolverTests {
    /// A fixed line (0,0)→(10,0) and a spline that starts at its end, through (14,3) and (20,2), the three other fit points fixed.
    struct LineAndSpline {
        var sketch = Sketch()
        let line: SketchEntityID
        let spline: SketchEntityID
        let joint: SketchEntityID
        let points: [SketchEntityID]

        init() {
            var sketch = Sketch()
            let line = sketch.addLine(Vector2(0, 0), Vector2(10, 0))
            let (start, end) = sketch.ends(line)
            var others: [SketchEntityID] = []
            for position in [Vector2(14, 3), Vector2(20, 2)] {
                let point = sketch.addPoint(position)
                sketch.add(.fix(point, at: position))
                others.append(point)
            }
            let points = [end] + others
            let spline = sketch.addSpline(through: points)
            sketch.add(.fix(start, at: Vector2(0, 0)))
            sketch.add(.fix(end, at: Vector2(10, 0)))
            (self.sketch, self.line, self.spline, self.joint, self.points) = (sketch, line, spline, end, points)
        }

        func resolved(_ solution: SketchSolution) throws -> [ResolvedSplineHandle] {
            try #require(sketch.splineDefinition(of: spline, solution: solution)).resolvedHandles()
        }
    }

    @Test func dofOfAnAutomaticSplineIsItsPoints() {
        var sketch = Sketch()
        sketch.addSpline([Vector2(0, 0), Vector2(4, 3), Vector2(9, 1), Vector2(12, 6)])
        #expect(SketchSolver.solve(sketch).status == .underConstrained(dof: 8))
    }

    @Test func aFullyFixedSplineIsSolved() {
        let fixture = LineAndSpline()
        #expect(SketchSolver.solve(fixture.sketch).status == .solved)
    }

    @Test func activeHandleAddsTwoDOF() {
        var fixture = LineAndSpline()
        fixture.sketch.activateSplineHandle(fixture.spline, at: 0, .tangent)
        #expect(SketchSolver.solve(fixture.sketch).status == .underConstrained(dof: 2))
        fixture.sketch.activateSplineHandle(fixture.spline, at: 0, .curvature)
        #expect(SketchSolver.solve(fixture.sketch).status == .underConstrained(dof: 4))
        fixture.sketch.activateSplineHandle(fixture.spline, at: 1, .tangent)
        #expect(SketchSolver.solve(fixture.sketch).status == .underConstrained(dof: 6))
    }

    @Test func tangentAtASplineEnd() throws {
        var fixture = LineAndSpline()
        fixture.sketch.activateSplineHandle(fixture.spline, at: 0, .tangent)
        fixture.sketch.add(.tangent(fixture.line, fixture.spline))
        let solution = SketchSolver.solve(fixture.sketch)
        // The tangent handle keeps one freedom (its length).
        #expect(solution.status == .underConstrained(dof: 1))
        let handle = try fixture.resolved(solution)[0]
        #expect(isClose(handle.tangent.y, 0, tolerance: 1e-7))
        #expect(handle.tangent.x > 0, "the spline continues the line, it doesn't fold back")
    }

    @Test func curvatureToALineMakesZeroCurvature() throws {
        var fixture = LineAndSpline()
        fixture.sketch.activateSplineHandle(fixture.spline, at: 0, .tangent)
        fixture.sketch.activateSplineHandle(fixture.spline, at: 0, .curvature)
        fixture.sketch.add(.curvature(fixture.line, fixture.spline))
        let solution = SketchSolver.solve(fixture.sketch)
        #expect(solution.status == .underConstrained(dof: 2))
        let handle = try fixture.resolved(solution)[0]
        #expect(isClose(handle.tangent.y, 0, tolerance: 1e-7))
        #expect(handle.tangent.x > 0)
        #expect(isClose(handle.curvature, 0, tolerance: 1e-8))
    }

    /// A quarter arc about the origin from (10,0) to (0,10), counter-clockwise.
    static func quarterArc(in sketch: inout Sketch) -> (arc: SketchEntityID, start: SketchEntityID, end: SketchEntityID) {
        let centre = sketch.addPoint(.zero)
        let start = sketch.addPoint(Vector2(10, 0))
        let end = sketch.addPoint(Vector2(0, 10))
        sketch.add(.fix(centre, at: .zero))
        sketch.add(.fix(start, at: Vector2(10, 0)))
        sketch.add(.fix(end, at: Vector2(0, 10)))
        return (sketch.addArc(center: centre, start: start, end: end), start, end)
    }

    @Test func curvatureToAnArcMatchesOneOverRAtItsEnd() throws {
        var sketch = Sketch()
        let (arc, _, end) = Self.quarterArc(in: &sketch)
        // The spline leaves the arc's end (0,10) towards the left, as the counter-clockwise arc would go on.
        let far = sketch.addPoint(Vector2(-8, 6))
        sketch.add(.fix(far, at: Vector2(-8, 6)))
        let spline = sketch.addSpline(through: [end, far])
        sketch.activateSplineHandle(spline, at: 0, .tangent)
        sketch.activateSplineHandle(spline, at: 0, .curvature)
        sketch.add(.curvature(arc, spline))
        let solution = SketchSolver.solve(sketch)
        #expect(solution.status.isUsable)
        let handle = try #require(sketch.splineDefinition(of: spline, solution: solution)).resolvedHandles()[0]
        #expect(isClose(handle.curvature, 0.1, tolerance: 1e-7), "the same turn as the counter-clockwise arc: +1/r")
        #expect(handle.tangent.x < 0 && isClose(handle.tangent.y, 0, tolerance: 1e-7))
    }

    @Test func curvatureToAnArcMatchesOneOverRAtItsStart() throws {
        var sketch = Sketch()
        let (arc, start, _) = Self.quarterArc(in: &sketch)
        // The spline arrives at the arc's start (10,0) from below, as the arc would be entered going on counter-clockwise.
        let far = sketch.addPoint(Vector2(9, -6))
        sketch.add(.fix(far, at: Vector2(9, -6)))
        let spline = sketch.addSpline(through: [far, start])
        sketch.activateSplineHandle(spline, at: 1, .tangent)
        sketch.activateSplineHandle(spline, at: 1, .curvature)
        sketch.add(.curvature(spline, arc))
        let solution = SketchSolver.solve(sketch)
        #expect(solution.status.isUsable)
        let handle = try #require(sketch.splineDefinition(of: spline, solution: solution)).resolvedHandles()[1]
        #expect(isClose(handle.curvature, 0.1, tolerance: 1e-7))
        #expect(handle.tangent.y > 0 && isClose(handle.tangent.x, 0, tolerance: 1e-7))
    }

    @Test func curvatureBetweenSplines() throws {
        var sketch = Sketch()
        let joint = sketch.addPoint(Vector2(10, 0))
        let leftEnd = sketch.addPoint(Vector2(0, 2))
        let rightEnd = sketch.addPoint(Vector2(20, -3))
        for (point, position) in [(joint, Vector2(10, 0)), (leftEnd, Vector2(0, 2)), (rightEnd, Vector2(20, -3))] {
            sketch.add(.fix(point, at: position))
        }
        let left = sketch.addSpline(through: [leftEnd, joint])
        let right = sketch.addSpline(through: [joint, rightEnd])
        sketch.activateSplineHandle(left, at: 1, .tangent)
        sketch.activateSplineHandle(left, at: 1, .curvature)
        sketch.activateSplineHandle(right, at: 0, .tangent)
        sketch.activateSplineHandle(right, at: 0, .curvature)
        sketch.add(.curvature(left, right))
        let solution = SketchSolver.solve(sketch)
        #expect(solution.status.isUsable)
        let incoming = try #require(sketch.splineDefinition(of: left, solution: solution)).resolvedHandles()[1]
        let outgoing = try #require(sketch.splineDefinition(of: right, solution: solution)).resolvedHandles()[0]
        let cross = SketchMath.cross(incoming.tangent, outgoing.tangent) / (incoming.tangent.length * outgoing.tangent.length)
        #expect(isClose(cross, 0, tolerance: 1e-7))
        #expect(SketchMath.dot(incoming.tangent, outgoing.tangent) > 0)
        #expect(isClose(incoming.curvature, outgoing.curvature, tolerance: 1e-8))
    }

    @Test func aLineAndASplineConstrainedAtBothEnds() throws {
        var sketch = Sketch()
        let a = sketch.addPoint(Vector2(0, 0))
        let b = sketch.addPoint(Vector2(10, 0))
        let middle = sketch.addPoint(Vector2(5, 4))
        for (point, position) in [(a, Vector2(0, 0)), (b, Vector2(10, 0)), (middle, Vector2(5, 4))] {
            sketch.add(.fix(point, at: position))
        }
        let line = sketch.addLine(from: a, to: b)
        let spline = sketch.addSpline(through: [b, middle, a])
        for index in [0, 2] {
            sketch.activateSplineHandle(spline, at: index, .tangent)
            sketch.activateSplineHandle(spline, at: index, .curvature)
        }
        sketch.add(.curvature(line, spline))
        let solution = SketchSolver.solve(sketch)
        #expect(solution.status.isUsable)
        let resolved = try #require(sketch.splineDefinition(of: spline, solution: solution)).resolvedHandles()
        #expect(isClose(resolved[0].curvature, 0, tolerance: 1e-8) && isClose(resolved[2].curvature, 0, tolerance: 1e-8))
        #expect(isClose(resolved[0].tangent.y, 0, tolerance: 1e-7) && isClose(resolved[2].tangent.y, 0, tolerance: 1e-7))
        #expect(resolved[0].tangent.x < 0 && resolved[2].tangent.x < 0, "a closed loop turns the same way at both joints")
    }

    @Test func conflictsAreNamed() {
        var sketch = Sketch()
        let a = sketch.addPoint(Vector2(0, 0))
        let joint = sketch.addPoint(Vector2(10, 0))
        let b = sketch.addPoint(Vector2(10, 10))
        let far = sketch.addPoint(Vector2(20, 3))
        for (point, position) in [(a, Vector2(0, 0)), (joint, Vector2(10, 0)), (b, Vector2(10, 10)), (far, Vector2(20, 3))] {
            sketch.add(.fix(point, at: position))
        }
        let horizontal = sketch.addLine(from: a, to: joint)
        let vertical = sketch.addLine(from: joint, to: b)
        let spline = sketch.addSpline(through: [joint, far])
        sketch.activateSplineHandle(spline, at: 0, .tangent)
        sketch.add(.tangent(horizontal, spline))
        sketch.add(.tangent(vertical, spline))
        let solution = SketchSolver.solve(sketch)
        guard case .overConstrained(let conflicts) = solution.status else {
            Issue.record("expected a conflict, got \(solution.status)")
            return
        }
        #expect(conflicts.count >= 2)
        #expect(solution.conflictMessages.contains { $0.contains("Tangent on") && $0.contains("Spline 1") })
    }

    @Test func fitPointsTakePointConstraintsAndDimensions() {
        var sketch = Sketch()
        let spline = sketch.addSpline([Vector2(0, 0), Vector2(4, 3), Vector2(9, 1)])
        let points = sketch.splineParts(of: spline)?.points ?? []
        sketch.add(.fix(points[0], at: .zero))
        sketch.add(.horizontalPoints(points[0], points[1]))
        sketch.addDimension(.distance(points[0], points[1]), value: 5)
        let solution = SketchSolver.solve(sketch)
        #expect(isClose(solution.points[points[1]] ?? .zero, Vector2(5, 0)))
        #expect(solution.status == .underConstrained(dof: 2))
    }

    @Test func draggingAFitPointKeepsAnActiveHandle() throws {
        var fixture = LineAndSpline()
        fixture.sketch.activateSplineHandle(fixture.spline, at: 2, .tangent)
        let before = try #require(fixture.sketch.splineHandleValue(fixture.spline, 2, .tangent))
        fixture.sketch.solved[fixture.points[2]] = nil
        let dragged = fixture.points[2]
        fixture.sketch.constraints = fixture.sketch.constraints.filter { if case .fix(let p, _) = $0.value { p != dragged } else { true } }
        let solution = SketchSolver.solve(fixture.sketch, dragging: [fixture.points[2]: Vector2(16, 6)])
        #expect(isClose(solution.points[fixture.points[2]] ?? .zero, Vector2(16, 6), tolerance: 1e-4))
        let handle = try #require(solution.handles[fixture.spline]?[2].tangent)
        #expect(isClose(handle, before, tolerance: 1e-6))
    }
}
