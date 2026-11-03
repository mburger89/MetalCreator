import CreatorGeometry
import Foundation
import Testing
@testable import CreatorSketch

/// The spline entity: storage, handles, saving, deleting, copying and the tools that refuse it.
struct SplineModelTests {
    func sketchWithHandles() -> (sketch: Sketch, spline: SketchEntityID) {
        var sketch = Sketch()
        let spline = sketch.addSpline([Vector2(0, 0), Vector2(4, 3), Vector2(9, 1), Vector2(12, 6)])
        sketch.activateSplineHandle(spline, at: 0, .tangent)
        sketch.activateSplineHandle(spline, at: 3, .curvature)
        return (sketch, spline)
    }

    @Test func labelsAndConstraintTitles() {
        var sketch = Sketch()
        let first = sketch.addSpline([.zero, Vector2(5, 5)])
        let second = sketch.addSpline([Vector2(9, 0), Vector2(5, 9)])
        let line = sketch.addLine(Vector2(0, 0), Vector2(1, 1))
        #expect(sketch.label(of: first) == "Spline 1" && sketch.label(of: second) == "Spline 2")
        let id = sketch.add(.curvature(line, second))
        #expect(sketch.label(of: .constraint(id)) == "Curvature on Line 1 and Spline 2")
        #expect(SketchConstraint.curvature(line, second).entities == [line, second])
    }

    @Test func activatingAHandleKeepsTheCurve() throws {
        var sketch = Sketch()
        let spline = sketch.addSpline([Vector2(0, 0), Vector2(4, 3), Vector2(9, 1), Vector2(12, 6)])
        let before = try #require(sketch.splineDefinition(of: spline)).curve()
        sketch.activateSplineHandle(spline, at: 1, .tangent)
        sketch.activateSplineHandle(spline, at: 1, .curvature)
        sketch.activateSplineHandle(spline, at: 2, .curvature)
        let after = try #require(sketch.splineDefinition(of: spline)).curve()
        #expect(zip(before.poles, after.poles).allSatisfy { isClose($0, $1, tolerance: 1e-9) })
        #expect(sketch.splineParts(of: spline)?.handles[1] == SplineHandleState(tangent: true, curvature: true))
        #expect(sketch.splineParts(of: spline)?.handles[0] == .automatic)
    }

    @Test func aSolveDoesNotChangeTheCurve() throws {
        let (sketch, spline) = sketchWithHandles()
        let before = try #require(sketch.splineDefinition(of: spline)).curve()
        var solved = sketch
        solved.remember(SketchSolver.solve(sketch))
        let after = try #require(solved.splineDefinition(of: spline)).curve()
        #expect(zip(before.poles, after.poles).allSatisfy { isClose($0, $1, tolerance: 1e-9) })
    }

    @Test func saveReopenSolveIsIdentical() throws {
        var (sketch, spline) = sketchWithHandles()
        let points = try #require(sketch.splineParts(of: spline)).points
        sketch.add(.fix(points[0], at: .zero))
        sketch.addDimension(.distance(points[0], points[1]), value: 6)
        sketch.remember(SketchSolver.solve(sketch))
        let data = try JSONEncoder().encode(sketch)
        let reopened = try JSONDecoder().decode(Sketch.self, from: data)
        #expect(reopened == sketch)
        let first = SketchSolver.solve(sketch)
        let second = SketchSolver.solve(reopened)
        #expect(first == second)
        let a = try #require(sketch.splineDefinition(of: spline, solution: first)).curve()
        let b = try #require(reopened.splineDefinition(of: spline, solution: second)).curve()
        #expect(zip(a.poles, b.poles).allSatisfy { isClose($0, $1, tolerance: 1e-12) })
    }

    @Test func releasingAHandleMakesItAutomaticAgain() throws {
        var (sketch, spline) = sketchWithHandles()
        let released = sketch.releaseSplineHandle(spline, at: 0, .tangent)
        #expect(released)
        #expect(sketch.splineParts(of: spline)?.handles[0] == .automatic)
        #expect(sketch.storedSplineHandles(of: spline)[0] == .automatic)
        #expect(SketchSolver.solve(sketch).status == .underConstrained(dof: 8 + 2))
    }

    @Test func releaseIsRefusedWhileAConstraintUsesTheHandle() {
        var sketch = Sketch()
        let line = sketch.addLine(Vector2(0, 0), Vector2(10, 0))
        let joint = sketch.ends(line).1
        let far = sketch.addPoint(Vector2(20, 3))
        let spline = sketch.addSpline(through: [joint, far])
        sketch.activateSplineHandle(spline, at: 0, .tangent)
        sketch.activateSplineHandle(spline, at: 0, .curvature)
        sketch.add(.tangent(line, spline))
        #expect(sketch.isSplineHandleConstrained(spline, at: 0, .tangent))
        #expect(!sketch.isSplineHandleConstrained(spline, at: 0, .curvature))
        let refused = sketch.releaseSplineHandle(spline, at: 0, .tangent)
        let released = sketch.releaseSplineHandle(spline, at: 0, .curvature)
        #expect(!refused && released)
        sketch.add(.curvature(line, spline))
        #expect(sketch.isSplineHandleConstrained(spline, at: 0, .curvature))
    }

    @Test func deletingTheLineDropsTheConstraintKeepsTheHandle() throws {
        var sketch = Sketch()
        let line = sketch.addLine(Vector2(0, 0), Vector2(10, 0))
        let joint = sketch.ends(line).1
        let far = sketch.addPoint(Vector2(20, 3))
        let spline = sketch.addSpline(through: [joint, far])
        sketch.activateSplineHandle(spline, at: 0, .tangent)
        sketch.activateSplineHandle(spline, at: 0, .curvature)
        sketch.add(.curvature(line, spline))
        let value = try #require(sketch.splineHandleValue(spline, 0, .tangent))
        sketch.removeEntity(line)
        #expect(sketch.constraints.isEmpty)
        #expect(sketch.splineParts(of: spline)?.handles[0] == SplineHandleState(tangent: true, curvature: true))
        #expect(sketch.splineHandleValue(spline, 0, .tangent) == value)
        #expect(SketchSolver.solve(sketch).status.isUsable)
    }

    @Test func deletingASplineTakesItsHandleValuesAndLeavesItsPoints() {
        var (sketch, spline) = sketchWithHandles()
        sketch.removeEntity(spline)
        #expect(sketch.solved[spline] == nil && sketch.entities[spline] == nil)
        #expect(sketch.ids(ofKind: "Point").count == 4)
        sketch.removeOrphanPoints(sketch.ids(ofKind: "Point"))
        #expect(sketch.entities.isEmpty)
    }

    @Test func mirrorReflectsTheHandles() throws {
        var (sketch, spline) = sketchWithHandles()
        let axis = sketch.addLine(Vector2(-5, -10), Vector2(-5, 10), isConstruction: true)
        let original = try #require(sketch.splineDefinition(of: spline)).resolvedHandles()
        let mirrored = try SketchCommands.mirror(sketch, entities: [spline], about: axis).sketch
        let copy = try #require(mirrored.ids(ofKind: "Spline").last)
        #expect(copy != spline)
        let handles = try #require(mirrored.splineDefinition(of: copy)).resolvedHandles()
        #expect(mirrored.splineParts(of: copy)?.handles == sketch.splineParts(of: spline)?.handles)
        // Reflected in a vertical line: x flips. A tangent reflects, a curvature flips sign.
        #expect(isClose(handles[0].tangent, Vector2(-original[0].tangent.x, original[0].tangent.y), tolerance: 1e-9))
        let curvature = original[3].secondDerivative
        #expect(isClose(handles[3].secondDerivative, Vector2(-curvature.x, curvature.y), tolerance: 1e-9))
        #expect(isClose(handles[3].curvature, -original[3].curvature, tolerance: 1e-9))
        // The reflected curve is the reflection of the curve.
        let a = try #require(sketch.splineDefinition(of: spline)).curve().polyline()
        let b = try #require(mirrored.splineDefinition(of: copy)).curve().polyline()
        #expect(zip(a, b).allSatisfy { isClose(Vector2(-10 - $0.x, $0.y), $1, tolerance: 1e-9) })
    }

    @Test func aLinearPatternCopiesSplinesWithTheirHandles() throws {
        let (sketch, spline) = sketchWithHandles()
        let edit = try SketchCommands.linearPattern(sketch, entities: [spline], direction: Vector2(1, 0), spacing: 20, count: 2)
        let copy = try #require(edit.sketch.ids(ofKind: "Spline").last)
        let a = try #require(sketch.splineDefinition(of: spline)).curve().polyline()
        let b = try #require(edit.sketch.splineDefinition(of: copy)).curve().polyline()
        #expect(zip(a, b).allSatisfy { isClose(Vector2($0.x + 20, $0.y), $1, tolerance: 1e-9) })
        #expect(edit.sketch.splineParts(of: copy)?.handles == sketch.splineParts(of: spline)?.handles)
    }

    @Test func trimExtendAndFilletRefuseSplines() {
        let (sketch, spline) = sketchWithHandles()
        #expect(throws: SketchCommandError("Trim doesn't work on splines yet.")) {
            try SketchCommands.trim(sketch, curve: spline, near: Vector2(4, 3))
        }
        #expect(throws: SketchCommandError("Extend doesn't work on splines yet.")) {
            try SketchCommands.extend(sketch, curve: spline, near: Vector2(12, 6))
        }
        let corner = sketch.splineParts(of: spline)?.points[0] ?? SketchEntityID(1)
        #expect(throws: SketchCommandError("Fillet doesn't work on splines yet.")) {
            try SketchCommands.fillet(sketch, corner: corner, radius: 1)
        }
    }

    @Test func aNonFiniteHandleMakesTheSketchNonFinite() {
        var (sketch, spline) = sketchWithHandles()
        #expect(sketch.isFinite)
        sketch.solved[spline] = .splineHandles([SplineHandle(tangent: Vector2(.nan, 0))])
        #expect(!sketch.isFinite)
    }
}
