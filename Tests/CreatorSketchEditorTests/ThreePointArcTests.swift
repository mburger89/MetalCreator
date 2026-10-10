import CreatorGeometry
import CreatorSketch
import Testing
@testable import CreatorSketchEditor

/// The 3-point arc (sketcher spec §8: "Arc (centre / 3-point) | A"): start, end, then a point it passes through.
@MainActor
struct ThreePointArcTests {
    func makeModel() -> (SketchEditorModel, RecordingHost) {
        let model = SketchEditorModel(sketch: Sketch(), plane: .xy)
        model.choose(.arcThreePoint)
        return (model, RecordingHost(model))
    }

    /// The one arc drawn: its centre, start and end positions.
    func arc(_ sketch: Sketch) throws -> (center: Vector2, start: Vector2, end: Vector2) {
        let id = try #require(sketch.entityIDs.first { if case .arc? = sketch.entities[$0]?.kind { true } else { false } })
        guard case .arc(let c, let s, let e)? = sketch.entities[id]?.kind,
              let center = sketch.position(of: c), let start = sketch.position(of: s), let end = sketch.position(of: e) else {
            throw ArcMissing()
        }
        return (center, start, end)
    }

    struct ArcMissing: Error {}

    func near(_ a: Vector2, _ b: Vector2) -> Bool { (a - b).length < 1e-6 }

    @Test func threeClicksDrawTheArcThroughTheThird() throws {
        let (model, host) = makeModel()
        model.click(at: Vector2(10, 0), tolerance: 1, modifiers: [])
        model.click(at: Vector2(0, 10), tolerance: 1, modifiers: [])
        #expect(host.commits.isEmpty, "two clicks place the ends")
        model.click(at: Vector2(7.0710678, 7.0710678), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.description) == ["Arc"])
        let drawn = try arc(model.sketch)
        #expect(near(drawn.center, .zero) && near(drawn.start, Vector2(10, 0)) && near(drawn.end, Vector2(0, 10)))
        #expect(model.solution.status.isUsable)
    }

    @Test func aThirdPointOnTheFarSideRunsTheArcTheLongWayRound() throws {
        let (model, _) = makeModel()
        model.click(at: Vector2(10, 0), tolerance: 1, modifiers: [])
        model.click(at: Vector2(0, 10), tolerance: 1, modifiers: [])
        model.click(at: Vector2(-7.0710678, -7.0710678), tolerance: 1, modifiers: [])
        let drawn = try arc(model.sketch)
        #expect(near(drawn.center, .zero))
        #expect(near(drawn.start, Vector2(0, 10)) && near(drawn.end, Vector2(10, 0)), "counter-clockwise from the end, through the third")
    }

    /// Review Focus 3: a third click in line with the ends draws nothing and keeps waiting.
    @Test func aThirdClickInLineDrawsNothing() {
        let (model, host) = makeModel()
        model.click(at: Vector2(0, 0), tolerance: 1, modifiers: [])
        model.click(at: Vector2(10, 0), tolerance: 1, modifiers: [])
        model.click(at: Vector2(20, 0), tolerance: 1, modifiers: [])
        model.click(at: Vector2(5, 0), tolerance: 1, modifiers: [])
        #expect(host.commits.isEmpty)
        model.click(at: Vector2(5, 5), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.description) == ["Arc"])
    }

    @Test func theRubberBandAndTheReadoutFollowEachStep() {
        let (model, _) = makeModel()
        model.click(at: Vector2(10, 0), tolerance: 1, modifiers: [])
        model.hover(at: Vector2(0, 10), tolerance: 1, modifiers: [])
        #expect(model.preview.curves == [.line(Vector2(10, 0), Vector2(0, 10))])
        #expect(model.pointerReadout == "14.1 mm · 135.0°", "the chord")
        model.click(at: Vector2(0, 10), tolerance: 1, modifiers: [])
        model.hover(at: Vector2(7.0710678, 7.0710678), tolerance: 1, modifiers: [])
        guard case .arc(let center, _, _)? = model.preview.curves.first else {
            Issue.record("no arc in the rubber band")
            return
        }
        #expect(near(center, .zero))
        #expect(model.pointerReadout == "R 10.0 mm · 90.0°")
    }

    @Test func arcsKeyTogglesBetweenTheTwoArcs() {
        let model = SketchEditorModel(sketch: Sketch(), plane: .xy)
        model.press(.arc)
        #expect(model.tool == .arc)
        model.press(.arc)
        #expect(model.tool == .arcThreePoint)
        model.press(.arc)
        #expect(model.tool == .arc)
        model.press(.line)
        #expect(model.tool == .line)
    }
}
