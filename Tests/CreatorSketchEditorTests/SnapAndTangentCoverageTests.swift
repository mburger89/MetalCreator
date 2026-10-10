import CreatorGeometry
import CreatorSketch
import Testing
@testable import CreatorSketchEditor

/// The S5b review's follow-ups: what a click that is only a size (a circle's radius, a centre arc's end) may snap
/// to, where a circle's centre and a 3-point arc's ends land when they are clicked on a curve, the tangent inference
/// from an arc's start, and the 3-point arc's end on its start's point.
@MainActor
struct SnapAndTangentCoverageTests {
    func makeModel(_ sketch: Sketch, tool: SketchTool) -> (SketchEditorModel, RecordingHost) {
        let model = SketchEditorModel(sketch: sketch, plane: .xy)
        model.choose(tool)
        return (model, RecordingHost(model))
    }

    /// A horizontal line along y = 0 from x = −50 to 50.
    func lineSketch() -> (sketch: Sketch, line: SketchEntityID) {
        var sketch = Sketch()
        let line = sketch.addLine(Vector2(-50, 0), Vector2(50, 0))
        return (sketch, line)
    }

    func constraints(_ sketch: Sketch) -> [SketchConstraint] {
        sketch.constraintIDs.compactMap { sketch.constraints[$0] }
    }

    /// The newest entity whose kind `matches`.
    func newest(in sketch: Sketch, where matches: (SketchEntityKind) -> Bool) -> SketchEntityID? {
        sketch.entityIDs.last { sketch.entities[$0].map { matches($0.kind) } ?? false }
    }

    func near(_ a: Vector2?, _ b: Vector2) -> Bool {
        guard let a else { return false }
        return (a - b).length < 1e-9
    }

    @Test func aCircleRadiusClickIsOnlyASizeSoNoCurveSnapsIt() throws {
        let (model, host) = makeModel(lineSketch().sketch, tool: .circle)
        model.click(at: Vector2(0, 20), tolerance: 1, modifiers: [])
        model.hover(at: Vector2(0, 0.4), tolerance: 1, modifiers: [])
        guard case .circle(_, let shown)? = model.preview.curves.first else {
            Issue.record("no rubber band")
            return
        }
        #expect(abs(shown - 19.6) < 1e-9, "the rubber band isn't snapped onto the line under the pointer")
        #expect(model.preview.inferred.isEmpty, "and shows no glyph, since nothing is inferred")
        model.click(at: Vector2(0, 0.4), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.description) == ["Circle"])
        let circle = try #require(newest(in: model.sketch) { if case .circle = $0 { true } else { false } })
        #expect(abs((model.sketch.radius(of: circle) ?? 0) - 19.6) < 1e-9)
        #expect(constraints(model.sketch).isEmpty)
    }

    @Test func aCentreArcsEndIsOnlyADirectionSoNoCurveHoldsIt() throws {
        var sketch = Sketch()
        sketch.addLine(Vector2(-50, 5), Vector2(50, 5))
        let (model, host) = makeModel(sketch, tool: .arc)
        model.click(at: Vector2(0, 0), tolerance: 1, modifiers: [])
        model.click(at: Vector2(10, 0), tolerance: 1, modifiers: [])
        // Off the arc's axis, so that snapping onto the line (to (3, 5)) would turn the ray: (3, 5.4) is the direction asked for.
        let asked = Vector2(3, 5.4)
        model.hover(at: asked, tolerance: 1, modifiers: [])
        #expect(model.preview.inferred.isEmpty)
        model.click(at: asked, tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.description) == ["Arc"])
        let arc = try #require(newest(in: model.sketch) { if case .arc = $0 { true } else { false } })
        guard case .arc(_, _, let end)? = model.sketch.entities[arc]?.kind else {
            Issue.record("no arc")
            return
        }
        #expect(near(model.sketch.position(of: end), asked * (10 / asked.length)),
                "the end lies on the start's radius, along the click and not along the snapped (3, 5)")
        #expect(constraints(model.sketch).isEmpty, "no point-on: the end was moved onto the radius, not held on the line")
    }

    @Test func aCircleCentreOnACurveIsHeldOnIt() throws {
        let (sketch, line) = lineSketch()
        let (model, host) = makeModel(sketch, tool: .circle)
        model.click(at: Vector2(20, 0.4), tolerance: 1, modifiers: [])
        model.click(at: Vector2(20, 12), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.description) == ["Circle"])
        let circle = try #require(newest(in: model.sketch) { if case .circle = $0 { true } else { false } })
        guard case .circle(let centre, _)? = model.sketch.entities[circle]?.kind else {
            Issue.record("no circle")
            return
        }
        #expect(near(model.sketch.position(of: centre), Vector2(20, 0)), "snapped onto the line")
        #expect(constraints(model.sketch) == [.pointOn(point: centre, curve: line)])
        #expect(abs((model.sketch.radius(of: circle) ?? 0) - 12) < 1e-9)
    }

    @Test func aThreePointArcsEndsOnACurveAreHeldOnIt() {
        let (sketch, line) = lineSketch()
        let (model, host) = makeModel(sketch, tool: .arcThreePoint)
        model.click(at: Vector2(10, 0.3), tolerance: 1, modifiers: [])
        model.click(at: Vector2(30, -0.3), tolerance: 1, modifiers: [])
        model.click(at: Vector2(20, 9), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.description) == ["Arc"])
        let held = constraints(model.sketch).filter { constraint in
            if case .pointOn(_, let curve) = constraint { curve == line } else { false }
        }
        #expect(held.count == 2, "the start and the end are each held on the line")
    }

    @Test func aLineLeavingAnArcsStartAlongItsTangentIsHeldTangent() throws {
        var sketch = Sketch()
        let center = sketch.addPoint(.zero)
        let start = sketch.addPoint(Vector2(10, 0))
        let end = sketch.addPoint(Vector2(0, 10))
        let arc = sketch.addArc(center: center, start: start, end: end)
        let (model, _) = makeModel(sketch, tool: .line)
        model.click(at: Vector2(10.2, 0), tolerance: 1, modifiers: [])
        let aimed = Vector2(10.4, -20)
        model.hover(at: aimed, tolerance: 1, modifiers: [])
        #expect(model.preview.inferred == [.tangent], "down the tangent at the start, away from the arc")
        model.click(at: aimed, tolerance: 1, modifiers: [])
        let line = try #require(newest(in: model.sketch) { if case .line = $0 { true } else { false } })
        guard case .line(let from, let to)? = model.sketch.entities[line]?.kind else {
            Issue.record("no line")
            return
        }
        #expect(from == start)
        #expect(near(model.sketch.position(of: to), Vector2(10, -20)), "the end snapped onto the tangent")
        #expect(constraints(model.sketch) == [.tangent(line, arc)])
    }

    @Test func aThreePointArcsEndOnItsStartsPointWaits() {
        var sketch = Sketch()
        sketch.addPoint(Vector2(10, 0))
        let (model, host) = makeModel(sketch, tool: .arcThreePoint)
        model.click(at: Vector2(10.2, 0), tolerance: 1, modifiers: [])
        model.click(at: Vector2(10.1, 0.1), tolerance: 1, modifiers: [])
        guard case .arcThroughFrom = model.drawState else {
            Issue.record("the end on the start's own point must not be taken: \(model.drawState)")
            return
        }
        model.click(at: Vector2(30, 0), tolerance: 1, modifiers: [])
        guard case .arcThrough = model.drawState else {
            Issue.record("a different end is taken: \(model.drawState)")
            return
        }
        #expect(host.commits.isEmpty)
    }

    @Test(arguments: [SketchTool.select, .dimension, .trim, .extend, .fillet, .mirror, .pattern])
    func hoveringWithAToolThatPlacesNoPointsShowsNoRubberBand(_ tool: SketchTool) {
        let (sketch, line) = lineSketch()
        let (model, _) = makeModel(sketch, tool: tool)
        model.hover(at: Vector2(20, 0.4), tolerance: 1, modifiers: [])
        #expect(model.hovered == line, "the entity under the pointer is still found")
        #expect(model.preview == .none)
    }
}
