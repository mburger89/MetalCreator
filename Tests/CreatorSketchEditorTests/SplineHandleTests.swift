import CreatorGeometry
import CreatorSketch
import Testing
@testable import CreatorSketchEditor

/// Handles: dragging activates and moves them, Release makes them automatic, Tangent and Curvature activate them, the
/// modify tools refuse splines, Mirror and Pattern copy them, and the overlay draws the curve and its handles.
@MainActor
struct SplineHandleTests {
    func fixture() -> (sketch: Sketch, spline: SketchEntityID) {
        var sketch = Sketch()
        let spline = sketch.addSpline([Vector2(0, 0), Vector2(15, 12), Vector2(30, 0)])
        return (sketch, spline)
    }

    func makeModel(_ sketch: Sketch) -> (SketchEditorModel, RecordingHost) {
        let model = SketchEditorModel(sketch: sketch, plane: .xy)
        return (model, RecordingHost(model))
    }

    func knob(_ model: SketchEditorModel, _ spline: SketchEntityID, _ index: Int, _ kind: SplineHandleKind,
              sign: Double = 1) throws -> Vector2 {
        let definition = try #require(model.sketch.splineDefinition(of: spline, solution: model.solution))
        return try #require(SplineHandleGeometry.knobs(of: spline, at: index, definition: definition)
            .first { $0.knob.kind == kind && $0.knob.sign == sign }).at
    }

    @Test func knobGeometryRoundTrips() {
        let point = Vector2(3, 4)
        let tangent = Vector2(0.8, 0.3)
        let scale = 2.5
        let at = SplineHandleGeometry.tangentKnob(point: point, tangent: tangent, scale: scale, sign: -1)
        #expect(close(SplineHandleGeometry.tangentValue(point: point, knob: at, scale: scale, sign: -1), tangent, tolerance: 1e-12))
        let second = Vector2(0.2, -0.4)
        let curvatureAt = SplineHandleGeometry.curvatureKnob(point: point, tangent: tangent, second: second, scale: scale)
        let back = SplineHandleGeometry.curvatureValue(point: point, knob: curvatureAt, tangent: tangent, second: second, scale: scale)
        #expect(back.map { close($0, second, tolerance: 1e-12) } == true)
    }

    @Test func draggingAHandleActivatesIt() throws {
        let (sketch, spline) = fixture()
        let (model, host) = makeModel(sketch)
        model.selection = [spline]
        let start = try knob(model, spline, 1, .tangent)
        #expect(model.beginDrag(at: start, tolerance: 0.5))
        #expect(model.sketch.splineParts(of: spline)?.handles[1].tangent == true, "active as soon as it is held")
        let target = start + Vector2(0, 3)
        model.drag(to: target)
        model.endDrag(at: target)
        #expect(host.commits.map(\.name) == ["Move Handle"])
        let definition = try #require(model.sketch.splineDefinition(of: spline, solution: model.solution))
        let value = try #require(definition.handles[1].tangent)
        let scale = SplineHandleGeometry.scale(points: definition.points, at: 1)
        let expected = SplineHandleGeometry.tangentValue(point: Vector2(15, 12), knob: target, scale: scale, sign: 1)
        #expect(close(value, expected, tolerance: 1e-3))
        #expect(model.sketch.splineParts(of: spline)?.handles[1].curvature == false)
    }

    @Test func aPressThatNeverMovesRecordsNothing() throws {
        let (sketch, spline) = fixture()
        let (model, host) = makeModel(sketch)
        model.selection = [spline]
        let before = model.sketch
        #expect(model.beginDrag(at: try knob(model, spline, 1, .curvature), tolerance: 0.5))
        model.endDrag(at: nil)
        #expect(host.commits.isEmpty && model.sketch == before)
    }

    @Test func draggingTheCurvatureKnobBendsTheCurve() throws {
        let (sketch, spline) = fixture()
        let (model, host) = makeModel(sketch)
        model.selection = [spline]
        let start = try knob(model, spline, 1, .curvature)
        let before = try #require(model.sketch.splineDefinition(of: spline, solution: model.solution)).resolvedHandles()[1].curvature
        #expect(model.beginDrag(at: start, tolerance: 0.5))
        let target = start + Vector2(0, 2)
        model.endDrag(at: target)
        let after = try #require(model.sketch.splineDefinition(of: spline, solution: model.solution)).resolvedHandles()[1].curvature
        #expect(host.commits.count == 1 && abs(after - before) > 1e-3)
        #expect(model.sketch.splineParts(of: spline)?.handles[1] == SplineHandleState(tangent: false, curvature: true))
    }

    @Test func releaseMakesItAutomatic() throws {
        var (sketch, spline) = fixture()
        sketch.activateSplineHandle(spline, at: 1, .tangent)
        let (model, host) = makeModel(sketch)
        let point = try #require(model.sketch.splineParts(of: spline)?.points[1])
        model.selection = [point]
        let rows = model.handleRows
        #expect(rows.map(\.label) == ["Tangent handle: Active", "Curvature handle: Automatic"])
        model.releaseHandle(of: spline, at: 1, .tangent)
        #expect(host.commits.map(\.name) == ["Release Handle"])
        #expect(model.sketch.splineParts(of: spline)?.handles[1] == .automatic)
        #expect(model.handleRows.map(\.label) == ["Tangent handle: Automatic", "Curvature handle: Automatic"])
    }

    @Test func releaseIsRefusedWhileConstrained() throws {
        var sketch = Sketch()
        let spline = sketch.addSpline([Vector2(0, 0), Vector2(10, 8), Vector2(20, 0)])
        let end = try #require(sketch.splineParts(of: spline)?.points.last)
        let line = sketch.addLine(from: end, to: sketch.addPoint(Vector2(30, 5)))
        let constraint = SketchConstraint.tangent(spline, line)
        sketch.activateHandles(for: constraint)
        sketch.add(constraint)
        let (model, host) = makeModel(sketch)
        model.releaseHandle(of: spline, at: 2, .tangent)
        #expect(host.commits.isEmpty)
        #expect(model.refusal == "A constraint uses that handle, so it can't be released.")
        #expect(model.sketch.splineParts(of: spline)?.handles[2].tangent == true)
    }

    @Test func curvatureButtonActivatesBothHandles() throws {
        var sketch = Sketch()
        let line = sketch.addLine(Vector2(-20, 0), Vector2(0, 0))
        let lineEnd = sketch.curveEnds(of: line)[1]
        let spline = sketch.addSpline(through: [lineEnd, sketch.addPoint(Vector2(10, 8)), sketch.addPoint(Vector2(20, 0))])
        let (model, host) = makeModel(sketch)
        model.selection = [line, spline]
        #expect(model.availableConstraints.contains(.curvature) && model.availableConstraints.contains(.tangent))
        model.addConstraint(.curvature)
        #expect(host.commits.map(\.name) == ["Add Curvature Constraint"])
        let joints = model.sketch.constraints.values
        #expect(joints.contains(.curvature(spline, line)) || joints.contains(.curvature(line, spline)))
        #expect(model.sketch.splineParts(of: spline)?.handles[0] == SplineHandleState(tangent: true, curvature: true))
        #expect(model.solution.status.isUsable)
    }

    @Test func tangentActivatesTheTangentHandleOnly() throws {
        var sketch = Sketch()
        let line = sketch.addLine(Vector2(-20, 0), Vector2(0, 0))
        let lineEnd = sketch.curveEnds(of: line)[1]
        let spline = sketch.addSpline(through: [lineEnd, sketch.addPoint(Vector2(10, 8)), sketch.addPoint(Vector2(20, 0))])
        let (model, host) = makeModel(sketch)
        model.selection = [line, spline]
        model.addConstraint(.tangent)
        #expect(host.commits.map(\.name) == ["Add Constraint"])
        #expect(model.sketch.splineParts(of: spline)?.handles[0] == SplineHandleState(tangent: true, curvature: false))
        #expect(model.solution.status.isUsable)
    }

    @Test func curvatureNeedsASplineAndACurve() {
        var sketch = Sketch()
        let first = sketch.addLine(Vector2(0, 0), Vector2(5, 0))
        let second = sketch.addLine(Vector2(5, 0), Vector2(5, 5))
        let (model, _) = makeModel(sketch)
        model.selection = [first, second]
        #expect(!model.availableConstraints.contains(.curvature))
    }

    @Test func trimExtendFilletRefuse() throws {
        var sketch = Sketch()
        let spline = sketch.addSpline([Vector2(0, 0), Vector2(10, 8), Vector2(20, 0)])
        let end = try #require(sketch.splineParts(of: spline)?.points.last)
        sketch.addLine(from: end, to: sketch.addPoint(Vector2(30, 5)))
        let (model, host) = makeModel(sketch)
        model.choose(.trim)
        model.click(at: Vector2(10, 8), tolerance: 0.5, modifiers: [])
        #expect(model.refusal == "Trim doesn't work on splines yet.")
        model.choose(.extend)
        model.click(at: Vector2(10, 8), tolerance: 0.5, modifiers: [])
        #expect(model.refusal == "Extend doesn't work on splines yet.")
        model.choose(.fillet)
        model.click(at: Vector2(20, 0), tolerance: 0.5, modifiers: [])
        #expect(model.refusal == "Fillet doesn't work on splines yet.")
        #expect(host.commits.isEmpty)
    }

    @Test func mirrorReflectsHandles() throws {
        let (base, spline) = fixture()
        var sketch = base
        sketch.activateSplineHandle(spline, at: 1, .tangent)
        sketch.activateSplineHandle(spline, at: 1, .curvature)
        let axis = sketch.addLine(Vector2(0, -20), Vector2(0, 40), isConstruction: true)
        let (model, host) = makeModel(sketch)
        model.choose(.mirror)
        model.selection = [spline]
        model.click(at: Vector2(0, 30), tolerance: 0.5, modifiers: [])
        #expect(host.commits.map(\.name) == ["Mirror"])
        let copy = try #require(splinesOf(model.sketch).first { $0 != spline })
        let original = try #require(model.sketch.splineDefinition(of: spline))
        let mirrored = try #require(model.sketch.splineDefinition(of: copy))
        #expect(close(mirrored.points[1], Vector2(-original.points[1].x, original.points[1].y), tolerance: 1e-9))
        let (a, b) = (try #require(original.handles[1].tangent), try #require(mirrored.handles[1].tangent))
        #expect(close(b, Vector2(-a.x, a.y), tolerance: 1e-9))
        _ = axis
    }

    @Test func patternCopiesSplines() throws {
        let (sketch, spline) = fixture()
        let (model, host) = makeModel(sketch)
        var withAxis = model.sketch
        let axis = withAxis.addLine(Vector2(0, -40), Vector2(0, -30), isConstruction: true)
        let model2 = SketchEditorModel(sketch: withAxis, plane: .xy)
        let host2 = RecordingHost(model2)
        model2.choose(.pattern)
        model2.selection = [spline]
        model2.options.patternCount = 3
        model2.options.patternSpacing = 5
        model2.click(at: Vector2(0, -35), tolerance: 0.5, modifiers: [])
        #expect(host2.commits.map(\.name) == ["Linear Pattern"])
        #expect(splinesOf(model2.sketch).count == 3)
        _ = (host, axis)
    }

    func splinesOf(_ sketch: Sketch) -> [SketchEntityID] {
        sketch.entityIDs.filter { sketch.splineParts(of: $0) != nil }
    }

    @Test func overlayDrawsTheCurveAndHandles() throws {
        let (sketch, spline) = fixture()
        let (model, _) = makeModel(sketch)
        let plain = model.overlay
        model.selection = [spline]
        let selected = model.overlay
        #expect(!plain.lines.isEmpty)
        #expect(selected.lines.count > plain.lines.count)
        #expect(selected.points.count == plain.points.count + 9, "three knobs at each of three fit points")
        let curve = try #require(model.sketch.splineDefinition(of: spline)).curve().polyline()
        #expect(plain.lines.count == curve.count - 1)
    }

    @Test func undoNames() {
        #expect(SketchStepName.addSpline == "Add Spline" && SketchStepName.moveHandle == "Move Handle")
        #expect(SketchStepName.releaseHandle == "Release Handle" && SketchStepName.addCurvatureConstraint == "Add Curvature Constraint")
    }

    @Test func keySPicksTheTool() {
        #expect(SketchTool.spline.title == "Spline")
        #expect(SketchTool.spline.key?.character == "s")
        let (model, _) = makeModel(Sketch())
        model.press(.spline)
        #expect(model.tool == .spline)
    }
    @Test func returnDuringAHandleDragRestoresTheSketch() throws {
        let (sketch, spline) = fixture()
        let (model, host) = makeModel(sketch)
        model.selection = [spline]
        let before = model.sketch
        let start = try knob(model, spline, 1, .tangent)
        #expect(model.beginDrag(at: start, tolerance: 0.5))
        model.drag(to: start + Vector2(0, 5))
        #expect(model.sketch != before)
        model.finish()
        #expect(model.sketch == before && host.commits.isEmpty)
        #expect(model.solution.status.isUsable)
    }

    @Test func aHandleDragWithoutAUsableSolveRecordsNothing() throws {
        let (base, spline) = fixture()
        var sketch = base
        // Two contradictory fixes on one point: every solve is over-constrained.
        let point = try #require(sketch.splineParts(of: spline)?.points[0])
        sketch.add(.fix(point, at: Vector2(0, 0)))
        sketch.add(.fix(point, at: Vector2(1, 1)))
        let (model, host) = makeModel(sketch)
        model.selection = [spline]
        let before = model.sketch
        let start = try knob(model, spline, 1, .tangent)
        #expect(model.beginDrag(at: start, tolerance: 0.5))
        let target = start + Vector2(0, 3)
        model.drag(to: target)
        model.endDrag(at: target)
        #expect(host.commits.isEmpty && model.sketch == before)
    }

    @Test func curvatureOnALineAndAnArcSaysWhy() {
        var sketch = Sketch()
        let corner = sketch.addPoint(Vector2(10, 0))
        let start = sketch.addPoint(Vector2(0, 0))
        let line = sketch.addLine(from: start, to: corner)
        let centre = sketch.addPoint(Vector2(10, 5))
        let end = sketch.addPoint(Vector2(15, 5))
        let arc = sketch.addArc(center: centre, start: corner, end: end)
        let (model, host) = makeModel(sketch)
        model.selection = [line, arc]
        model.addConstraint(.curvature)
        #expect(model.refusal == "A line and an arc can't meet with equal curvature.")
        #expect(host.commits.isEmpty)
    }
}

func close(_ a: Vector2, _ b: Vector2, tolerance: Double) -> Bool { (a - b).length <= tolerance }
