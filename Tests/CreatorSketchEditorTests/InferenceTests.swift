import CreatorGeometry
import CreatorSketch
import Testing
@testable import CreatorSketchEditor

/// Point-on and tangent inference (sketcher spec §8): a click on a curve puts a new point on it (held there by
/// point-on), and a line leaving an arc's end along its tangent snaps onto it and is held tangent.
@MainActor
struct InferenceTests {
    func makeModel(_ sketch: Sketch, tool: SketchTool) -> (SketchEditorModel, RecordingHost) {
        let model = SketchEditorModel(sketch: sketch, plane: .xy)
        model.choose(tool)
        return (model, RecordingHost(model))
    }

    func constraints(_ sketch: Sketch) -> [SketchConstraint] {
        sketch.constraintIDs.compactMap { sketch.constraints[$0] }
    }

    /// The newest line's start and end points.
    func newestLine(_ sketch: Sketch) -> (id: SketchEntityID, start: SketchEntityID, end: SketchEntityID)? {
        for id in sketch.entityIDs.reversed() {
            if case .line(let start, let end)? = sketch.entities[id]?.kind { return (id, start, end) }
        }
        return nil
    }

    /// An arc around the origin, radius 10, from (10, 0) counter-clockwise to 45°.
    func arcSketch() -> (sketch: Sketch, arc: SketchEntityID, end: SketchEntityID) {
        var sketch = Sketch()
        let center = sketch.addPoint(.zero)
        let start = sketch.addPoint(Vector2(10, 0))
        let end = sketch.addPoint(Vector2(10, 10) * (1 / 2.0.squareRoot()))
        let arc = sketch.addArc(center: center, start: start, end: end)
        return (sketch, arc, end)
    }

    @Test func aLineEndingOnACurveIsHeldOnIt() throws {
        var sketch = Sketch()
        let base = sketch.addLine(Vector2(0, 0), Vector2(40, 0))
        let (model, host) = makeModel(sketch, tool: .line)
        model.click(at: Vector2(10, 15), tolerance: 1, modifiers: [])
        model.click(at: Vector2(20, 0.4), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.description) == ["Line"])
        let line = try #require(newestLine(model.sketch))
        #expect(model.sketch.position(of: line.end) == Vector2(20, 0), "snapped onto the curve")
        #expect(constraints(model.sketch) == [.pointOn(point: line.end, curve: base)])
    }

    /// Review Focus 4: a click near both a point and the curve through it shares the point (coincident by
    /// construction) and adds no point-on.
    @Test func aPointWinsOverTheCurveThroughIt() throws {
        var sketch = Sketch()
        sketch.addLine(Vector2(0, 0), Vector2(40, 0))
        let (model, _) = makeModel(sketch, tool: .line)
        model.click(at: Vector2(10, 15), tolerance: 1, modifiers: [])
        model.click(at: Vector2(39.6, 0.3), tolerance: 1, modifiers: [])
        let line = try #require(newestLine(model.sketch))
        #expect(model.sketch.position(of: line.end) == Vector2(40, 0))
        #expect(constraints(model.sketch).isEmpty)
    }

    @Test func thePointToolPutsAPointOnACircle() throws {
        var sketch = Sketch()
        let circle = sketch.addCircle(center: .zero, radius: 10)
        let (model, host) = makeModel(sketch, tool: .point)
        model.hover(at: Vector2(0.3, 10.4), tolerance: 1, modifiers: [])
        let marked = try #require(model.preview.points.first)
        #expect(abs(marked.length - 10) < 1e-9, "the rubber band marks the snapped place")
        model.click(at: Vector2(0.3, 10.4), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.description) == ["Point"])
        let point = try #require(model.sketch.entityIDs.last)
        #expect(constraints(model.sketch) == [.pointOn(point: point, curve: circle)])
        #expect(abs((model.sketch.position(of: point) ?? .zero).length - 10) < 1e-9)
    }

    @Test func aLineLeavingAnArcAlongItsTangentIsHeldTangent() throws {
        let fixture = arcSketch()
        let (model, _) = makeModel(fixture.sketch, tool: .line)
        let corner = Vector2(10, 10) * (1 / 2.0.squareRoot())
        let tangent = Vector2(-1, 1) * (1 / 2.0.squareRoot())
        model.click(at: corner + Vector2(0.2, 0), tolerance: 1, modifiers: [])
        let aimed = corner + tangent * 20 + Vector2(0.4, 0.3)
        model.hover(at: aimed, tolerance: 1, modifiers: [])
        guard case .line(_, let shown)? = model.preview.curves.first else {
            Issue.record("no rubber band")
            return
        }
        #expect((shown - (corner + tangent * 20)).length < 0.5, "the rubber band snaps onto the tangent")
        model.click(at: aimed, tolerance: 1, modifiers: [])
        let line = try #require(newestLine(model.sketch))
        #expect(line.start == fixture.end, "the line starts on the arc's end")
        #expect(constraints(model.sketch) == [.tangent(line.id, fixture.arc)])
        let end = try #require(model.sketch.position(of: line.end))
        let offset = end - corner
        #expect(abs(offset.x * tangent.y - offset.y * tangent.x) < 1e-9, "the end is on the tangent")
        #expect(model.solution.status.isUsable)
    }

    @Test func commandSuppressesTangentInference() throws {
        let fixture = arcSketch()
        let (model, _) = makeModel(fixture.sketch, tool: .line)
        let corner = Vector2(10, 10) * (1 / 2.0.squareRoot())
        let tangent = Vector2(-1, 1) * (1 / 2.0.squareRoot())
        model.click(at: corner, tolerance: 1, modifiers: [])
        model.click(at: corner + tangent * 20 + Vector2(0.4, 0.3), tolerance: 1, modifiers: .command)
        #expect(constraints(model.sketch).isEmpty)
    }

    /// ⌘ suppresses point-on too (sketcher spec §8: "holding ⌘ suppresses inference"): the end stays where it was
    /// clicked, free, and so does a lone point.
    @Test func commandSuppressesPointOn() throws {
        var sketch = Sketch()
        sketch.addLine(Vector2(0, 0), Vector2(40, 0))
        let (model, host) = makeModel(sketch, tool: .line)
        model.click(at: Vector2(10, 15), tolerance: 1, modifiers: [])
        model.click(at: Vector2(20, 0.4), tolerance: 1, modifiers: .command)
        let line = try #require(newestLine(model.sketch))
        let end = try #require(model.sketch.position(of: line.end))
        #expect((end - Vector2(20, 0.4)).length < 1e-9, "not snapped onto the curve")
        model.choose(.point)
        model.click(at: Vector2(30, 0.4), tolerance: 1, modifiers: .command)
        #expect(host.commits.map(\.description) == ["Line", "Point"])
        #expect(constraints(model.sketch).isEmpty)
    }

    @Test func aLineAwayFromTheTangentStillInfersHorizontal() throws {
        let fixture = arcSketch()
        let (model, _) = makeModel(fixture.sketch, tool: .line)
        let corner = Vector2(10, 10) * (1 / 2.0.squareRoot())
        model.click(at: corner, tolerance: 1, modifiers: [])
        model.click(at: corner + Vector2(20, 0.3), tolerance: 1, modifiers: [])
        let line = try #require(newestLine(model.sketch))
        #expect(constraints(model.sketch) == [.horizontal(line.id)])
    }
}
