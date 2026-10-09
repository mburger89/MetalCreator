import CreatorGeometry
import CreatorSketch
import CreatorViewport
import Testing
@testable import CreatorSketchEditor

/// Drawing (sketcher spec §8): lines chain from click to click and infer horizontal and vertical (⌘ suppresses it),
/// clicks snap onto existing points (shared, so coincidence is structural), circles and arcs, points, construction,
/// Esc and ⏎. Each finished curve is one commit.
@MainActor
struct DrawingTests {
    func makeModel(_ sketch: Sketch = Sketch()) -> (SketchEditorModel, RecordingHost) {
        let model = SketchEditorModel(sketch: sketch, plane: .xy)
        return (model, RecordingHost(model))
    }

    func lines(_ sketch: Sketch) -> [(start: SketchEntityID, end: SketchEntityID)] {
        sketch.entityIDs.compactMap { id in
            if case .line(let start, let end)? = sketch.entities[id]?.kind { return (start, end) }
            return nil
        }
    }

    @Test func linesChainAndInferHorizontalAndVertical() throws {
        let (model, host) = makeModel()
        model.choose(.line)
        model.click(at: Vector2(0, 0), tolerance: 1, modifiers: [])
        #expect(host.commits.isEmpty, "the first click only starts the chain")
        model.click(at: Vector2(20, 0.4), tolerance: 1, modifiers: [])
        model.click(at: Vector2(20.5, 15), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.description) == ["Line", "Line"])
        let sketch = model.sketch
        let drawn = lines(sketch)
        #expect(drawn.count == 2 && drawn[0].end == drawn[1].start, "the chain shares its points")
        #expect(sketch.position(of: drawn[0].end) == Vector2(20, 0), "snapped onto the horizontal")
        let constraints = sketch.constraintIDs.compactMap { sketch.constraints[$0] }
        #expect(constraints.contains { if case .horizontal = $0 { true } else { false } })
        #expect(constraints.contains { if case .vertical = $0 { true } else { false } })
    }

    @Test func commandSuppressesInference() {
        let (model, _) = makeModel()
        model.choose(.line)
        model.click(at: Vector2(0, 0), tolerance: 1, modifiers: [])
        model.click(at: Vector2(20, 0.4), tolerance: 1, modifiers: .command)
        #expect(model.sketch.constraints.isEmpty)
        #expect(model.sketch.position(of: lines(model.sketch)[0].end) == Vector2(20, 0.4))
    }

    @Test func aClickNearAPointSharesItAndClosesTheLoop() {
        let (model, _) = makeModel()
        model.choose(.line)
        for corner in [Vector2(0, 0), Vector2(30, 0), Vector2(30, 20), Vector2(0, 20), Vector2(0.3, 0.2)] {
            model.click(at: corner, tolerance: 1, modifiers: [])
        }
        let drawn = lines(model.sketch)
        #expect(drawn.count == 4)
        #expect(drawn[3].end == drawn[0].start, "the last line ends on the first point")
        #expect(model.sketch.entities.count == 8, "four points, four lines")
    }

    @Test func escapeEndsTheChainThenFinishes() {
        let (model, host) = makeModel()
        model.choose(.line)
        model.click(at: Vector2(0, 0), tolerance: 1, modifiers: [])
        model.hover(at: Vector2(10, 10), tolerance: 1, modifiers: [])
        #expect(model.preview.curves == [.line(Vector2(0, 0), Vector2(10, 10))], "the rubber band follows the pointer")
        model.escape()
        #expect(model.preview == .none && host.finishes == 0)
        model.click(at: Vector2(5, 5), tolerance: 1, modifiers: [])
        model.escape()
        model.escape()
        #expect(host.finishes == 1)
        #expect(host.commits.isEmpty)
    }

    @Test func circlesTakeACentreAndARadius() throws {
        let (model, host) = makeModel()
        model.choose(.circle)
        model.click(at: Vector2(10, 10), tolerance: 1, modifiers: [])
        model.click(at: Vector2(13, 14), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.description) == ["Circle"])
        let circles = model.sketch.entityIDs.filter { id in
            if case .circle? = model.sketch.entities[id]?.kind { return true }
            return false
        }
        let circle = try #require(circles.first)
        #expect(abs((model.sketch.radius(of: circle) ?? 0) - 5) < 1e-9)
    }

    @Test func arcsTakeACentreAStartAndAnEndOnTheStartsRadius() throws {
        let (model, host) = makeModel()
        model.choose(.arc)
        model.click(at: Vector2(0, 0), tolerance: 1, modifiers: [])
        model.click(at: Vector2(10, 0), tolerance: 1, modifiers: [])
        model.click(at: Vector2(0, 3), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.description) == ["Arc"])
        let sketch = model.sketch
        let ends = sketch.entityIDs.compactMap { id -> SketchEntityID? in
            if case .arc(_, _, let end)? = sketch.entities[id]?.kind { return end }
            return nil
        }
        let end = try #require(ends.first.flatMap { sketch.position(of: $0) })
        #expect(abs(end.x) < 1e-9 && abs(end.y - 10) < 1e-9)
    }

    @Test func pointsGoWhereNoPointIs() {
        let (model, host) = makeModel()
        model.choose(.point)
        model.click(at: Vector2(1, 1), tolerance: 1, modifiers: [])
        model.click(at: Vector2(1.2, 1.1), tolerance: 1, modifiers: [])
        #expect(host.commits.count == 1 && model.sketch.entities.count == 1)
    }

    @Test func constructionAppliesToNewGeometryAndToTheSelection() throws {
        let (model, host) = makeModel()
        model.toggleConstruction()
        model.choose(.line)
        model.click(at: Vector2(0, 0), tolerance: 1, modifiers: [])
        model.click(at: Vector2(10, 5), tolerance: 1, modifiers: [])
        let line = try #require(model.sketch.entityIDs.last)
        #expect(model.sketch.entities[line]?.isConstruction == true)
        model.selection = [line]
        model.toggleConstruction()
        #expect(model.sketch.entities[line]?.isConstruction == false)
        #expect(host.commits.last?.description == "Make Normal Geometry")
    }

    @Test func viewportClicksLandOnThePlane() {
        let (model, host) = makeModel()
        model.choose(.point)
        let projector = ViewportProjector(pose: CameraPose(target: Vector3(5, 5, 0), distance: 100, pitch: .pi / 2,
                                                           projection: .orthographic),
                                          size: ViewportSize(width: 400, height: 300))
        #expect(model.clicked(at: ScreenPoint(200, 150), modifiers: [], projector: projector), "every click is the editor's")
        let point = model.sketch.entityIDs.first.flatMap { model.sketch.position(of: $0) }
        #expect(point.map { abs($0.x - 5) < 1e-9 && abs($0.y - 5) < 1e-9 } == true)
        #expect(host.commits.count == 1)
    }

    /// Review Focus 3: a double click draws nothing degenerate and stores nothing.
    @Test func clickingTheSameSpotTwiceDrawsNothing() {
        let (model, host) = makeModel()
        model.choose(.line)
        model.click(at: Vector2(3, 3), tolerance: 1, modifiers: [])
        model.click(at: Vector2(3, 3), tolerance: 1, modifiers: [])
        model.choose(.circle)
        model.click(at: Vector2(9, 9), tolerance: 1, modifiers: [])
        model.click(at: Vector2(9, 9), tolerance: 1, modifiers: [])
        model.choose(.arc)
        model.click(at: Vector2(20, 0), tolerance: 1, modifiers: [])
        model.click(at: Vector2(20, 0), tolerance: 1, modifiers: [])
        #expect(host.commits.isEmpty && model.sketch.entities.isEmpty)
    }

    /// Review Focus 4: with the plane seen edge-on there is no point under the pointer; the click is still the
    /// editor's, so nothing behind the sketch is selected, and nothing is drawn.
    @Test func aClickOffThePlaneIsClaimedButDrawsNothing() {
        let (model, host) = makeModel()
        model.choose(.point)
        let edgeOn = ViewportProjector(pose: CameraPose(distance: 100, pitch: 0, projection: .orthographic),
                                       size: ViewportSize(width: 400, height: 300))
        #expect(model.clicked(at: ScreenPoint(200, 150), modifiers: [], projector: edgeOn))
        model.pointerMoved(to: ScreenPoint(210, 150), projector: edgeOn)
        #expect(host.commits.isEmpty && model.preview == .none)
    }
}
