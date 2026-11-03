import CreatorGeometry
import CreatorSketch
import CreatorViewport
import Testing
@testable import CreatorSketchEditor

/// The Spline tool: drawing, finishing, reusing points and inferring Tangent.
@MainActor
struct SplineToolTests {
    func makeModel(_ sketch: Sketch = Sketch()) -> (SketchEditorModel, RecordingHost) {
        let model = SketchEditorModel(sketch: sketch, plane: .xy)
        model.choose(.spline)
        return (model, RecordingHost(model))
    }

    func splines(_ sketch: Sketch) -> [SketchEntityID] {
        sketch.entityIDs.filter { sketch.splineParts(of: $0) != nil }
    }

    func click(_ model: SketchEditorModel, _ x: Double, _ y: Double, _ modifiers: ViewportModifiers = []) {
        model.click(at: Vector2(x, y), tolerance: 1, modifiers: modifiers)
    }

    @Test func drawingASplinePlacesFitPoints() throws {
        let (model, host) = makeModel()
        click(model, 0, 0)
        click(model, 10, 8)
        click(model, 20, 0)
        guard case .splineThrough(let placed) = model.drawState else { Issue.record("not drawing"); return }
        #expect(placed.count == 3 && host.commits.isEmpty && model.sketch.entities.isEmpty, "nothing is stored until it finishes")
        model.hover(at: Vector2(30, 6), tolerance: 1, modifiers: [])
        #expect(model.preview.curves.contains { if case .spline(let through) = $0 { through.count == 4 } else { false } })
        #expect(model.preview.points.count == 4)
        click(model, 30, 6)
        click(model, 30, 6)
        #expect(host.commits.map(\.description) == ["Spline"] && host.commits.map(\.name) == ["Add Spline"])
        let spline = try #require(splines(model.sketch).first)
        #expect(model.sketch.splineParts(of: spline)?.points.count == 4)
        #expect(model.drawState == .idle && model.solution.status.isUsable)
        #expect(model.sketch.splineDefinition(of: spline)?.points.last == Vector2(30, 6))
    }

    @Test func aDoubleClickFinishesAtTheLastPoint() {
        let (model, host) = makeModel()
        click(model, 0, 0)
        click(model, 10, 5)
        click(model, 10.2, 5.1)
        #expect(host.commits.count == 1 && splines(model.sketch).count == 1)
    }

    @Test func finishingKeepsTwoOrMore() throws {
        let (model, host) = makeModel()
        click(model, 0, 0)
        click(model, 10, 5)
        model.finish()
        #expect(host.finishes == 0, "Return ends the spline; the sketch is left by the next one")
        #expect(host.commits.count == 1 && splines(model.sketch).count == 1)
        model.finish()
        #expect(host.finishes == 1)
    }

    @Test func escWithOnePointDiscards() {
        let (model, host) = makeModel()
        click(model, 0, 0)
        model.escape()
        #expect(host.commits.isEmpty && model.sketch.entities.isEmpty && model.drawState == .idle)
        click(model, 0, 0)
        click(model, 10, 5)
        click(model, 20, 0)
        model.escape()
        #expect(host.commits.count == 1 && model.sketch.splineParts(of: splines(model.sketch)[0])?.points.count == 3)
    }

    @Test func reusesExistingEndpoints() throws {
        var sketch = Sketch()
        let start = sketch.addPoint(Vector2(0, 0))
        let end = sketch.addPoint(Vector2(20, 0))
        let (model, _) = makeModel(sketch)
        click(model, 0.2, 0.1)
        click(model, 10, 6)
        click(model, 20.1, -0.1)
        model.finish()
        let spline = try #require(splines(model.sketch).first)
        let parts = try #require(model.sketch.splineParts(of: spline))
        #expect(parts.points.first == start && parts.points.last == end && parts.points.count == 3)
        #expect(model.sketch.entities.count == 4, "two points were shared; only the middle one is new, plus the spline")
    }

    @Test func infersTangentAtAnArcEnd() throws {
        var sketch = Sketch()
        let center = sketch.addPoint(.zero)
        let from = sketch.addPoint(Vector2(10, 0))
        let to = sketch.addPoint(Vector2(0, 10))
        let arc = sketch.addArc(center: center, start: from, end: to)
        let (model, _) = makeModel(sketch)
        model.hover(at: Vector2(0, 10), tolerance: 1, modifiers: [])
        #expect(model.preview.inferred == [.tangent])
        click(model, 0, 10)
        click(model, -10, 14)
        click(model, -20, 10)
        model.finish()
        let spline = try #require(splines(model.sketch).first)
        #expect(model.sketch.constraints.values.contains(.tangent(spline, arc)))
        #expect(model.sketch.splineParts(of: spline)?.handles.first?.tangent == true)
        #expect(model.solution.status.isUsable)
        let definition = try #require(model.sketch.splineDefinition(of: spline, solution: model.solution))
        let tangent = definition.resolvedHandles()[0].tangent
        let radius = try #require(model.solution.points[to]) - (try #require(model.solution.points[center]))
        let cross = tangent.x * radius.x + tangent.y * radius.y
        #expect(abs(cross) < 1e-6 * tangent.length * radius.length, "the spline leaves the arc's end along its tangent")
    }

    @Test func commandSuppressesInference() throws {
        var sketch = Sketch()
        let center = sketch.addPoint(.zero)
        let from = sketch.addPoint(Vector2(10, 0))
        let to = sketch.addPoint(Vector2(0, 10))
        sketch.addArc(center: center, start: from, end: to)
        let (model, _) = makeModel(sketch)
        model.hover(at: Vector2(0, 10), tolerance: 1, modifiers: [.command])
        #expect(model.preview.inferred == [.coincident])
        click(model, 0, 10, [.command])
        click(model, -10, 14)
        model.finish()
        #expect(!model.sketch.constraints.values.contains { if case .tangent = $0 { true } else { false } })
    }

    @Test func aClickOnASplineDoesNotHoldAPointOnIt() {
        var sketch = Sketch()
        sketch.addSpline([Vector2(0, 0), Vector2(10, 6), Vector2(20, 0)])
        let model = SketchEditorModel(sketch: sketch, plane: .xy)
        let target = model.anchor(at: Vector2(10, 6.2), tolerance: 1, suppressed: false)
        #expect(target.curve == nil)
    }
}
