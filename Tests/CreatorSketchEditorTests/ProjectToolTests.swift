import CreatorGeometry
import CreatorKernel
import CreatorSketch
import CreatorViewport
import Testing
@testable import CreatorSketchEditor

/// The Project tool (sketcher spec §8): a click on the model's edge or face becomes fixed projected curves in the sketch,
/// each with a fresh reference, handed to the host with the picks to store. One undo step.
@MainActor
struct ProjectToolTests {
    let pick = EdgePick(key: EdgeKey([], []), matchCount: 1)
    let projector = ViewportProjector(pose: CameraPose(target: .zero, distance: 100, pitch: .pi / 2, projection: .orthographic),
                                      size: ViewportSize(width: 400, height: 300))

    func candidate(_ x: Double, solid: Int = 0) -> ProjectionCandidate {
        ProjectionCandidate(curve: .line(Vector2(x, 0), Vector2(x + 30, 0)), pick: pick, solid: solid)
    }

    func makeModel(_ sketch: Sketch = Sketch(), answering candidates: [ProjectionCandidate] = [],
                   skipped: [String] = []) -> (SketchEditorModel, RecordingHost) {
        let model = SketchEditorModel(sketch: sketch, plane: .xz)
        model.choose(.project)
        model.events.projection = { _, _ in ProjectionResolution(candidates: candidates, skipped: skipped) }
        return (model, RecordingHost(model))
    }

    func projected(_ sketch: Sketch) -> [ProjectionSource] {
        sketch.entityIDs.compactMap { id in
            if case .projected(let source)? = sketch.entities[id]?.kind { source } else { nil }
        }
    }

    @Test func projectDeclinesThePlaneClickAndTakesTheModelsPick() {
        let (model, _) = makeModel(answering: [candidate(0)])
        #expect(!model.clicked(at: ScreenPoint(200, 150), modifiers: [], projector: projector), "so the viewport picks the model")
        #expect(model.clickedModel(.edge(solid: 0, EdgeID(1)), at: ScreenPoint(200, 150), modifiers: [], projector: projector))
        model.choose(.line)
        #expect(model.clicked(at: ScreenPoint(200, 150), modifiers: [], projector: projector))
        #expect(!model.clickedModel(.edge(solid: 0, EdgeID(1)), at: ScreenPoint(200, 150), modifiers: [], projector: projector),
                "any other tool leaves the pick to the host")
    }

    @Test func aPickedEdgeIsAFixedProjectedEntityCommittedWithItsPick() throws {
        var asked: [(PickTarget, Plane)] = []
        let (model, host) = makeModel(answering: [candidate(5, solid: 2)])
        model.events.projection = { target, plane in
            asked.append((target, plane))
            return ProjectionResolution(candidates: [self.candidate(5, solid: 2)], skipped: [])
        }
        model.project(.edge(solid: 2, EdgeID(7)))
        #expect(asked.count == 1 && asked[0].0 == .edge(solid: 2, EdgeID(7)) && asked[0].1 == .xz, "the host gets the pick and the plane")
        #expect(host.commits.map(\.description) == ["Project"])
        let commit = try #require(host.commits.first)
        #expect(commit.projections == [ProjectionWrite(reference: "edge1", pick: pick, solid: 2)])
        #expect(projected(model.sketch) == [ProjectionSource(reference: "edge1", curve: .line(Vector2(5, 0), Vector2(35, 0)))])
        #expect(model.sketch.constraintIDs.isEmpty && model.solution.status.isUsable)
    }

    @Test func aFacePicksOneProjectionPerEdgeAndLaterOnesTakeTheNextReferences() {
        let (model, host) = makeModel(answering: [candidate(0), candidate(100), candidate(200)])
        model.project(.face(solid: 0, FaceID(1)))
        #expect(projected(model.sketch).map(\.reference) == ["edge1", "edge2", "edge3"])
        #expect(host.commits.count == 1, "one undo step for the face")
        model.events.projection = { _, _ in ProjectionResolution(candidates: [self.candidate(300)], skipped: []) }
        model.project(.edge(solid: 0, EdgeID(2)))
        #expect(projected(model.sketch).map(\.reference) == ["edge1", "edge2", "edge3", "edge4"])
        #expect(host.commits.last?.projections.map(\.reference) == ["edge4"], "only the new one is written")
    }

    @Test func aReferenceInUseIsNeverReusedAndAFreedOneIsTaken() {
        var sketch = Sketch()
        sketch.add(SketchEntity(.projected(ProjectionSource(reference: "edge1", curve: .line(Vector2(0, 50), Vector2(1, 50))))))
        sketch.add(SketchEntity(.projected(ProjectionSource(reference: "edge3", curve: .line(Vector2(0, 60), Vector2(1, 60))))))
        let (model, _) = makeModel(sketch, answering: [candidate(0), candidate(100)])
        model.project(.face(solid: 0, FaceID(1)))
        #expect(projected(model.sketch).map(\.reference) == ["edge1", "edge3", "edge2", "edge4"])
    }

    @Test func anEdgeAlreadyProjectedIsLeftOutWithAReason() {
        let (model, host) = makeModel(answering: [candidate(0)])
        model.project(.edge(solid: 0, EdgeID(1)))
        model.project(.edge(solid: 0, EdgeID(1)))
        #expect(host.commits.count == 1 && projected(model.sketch).count == 1, "nothing is stored twice")
        #expect(model.refusal == "That edge is already projected.")
    }

    @Test func whatCantBeProjectedIsSaidInWordsAndNothingIsStored() {
        let (model, host) = makeModel(skipped: ["Edge 3 can't be projected: it is perpendicular to the sketch plane."])
        model.project(.edge(solid: 0, EdgeID(3)))
        #expect(host.commits.isEmpty)
        #expect(model.refusal == "Edge 3 can't be projected: it is perpendicular to the sketch plane.")
        let (silent, _) = makeModel()
        silent.project(.face(solid: 0, FaceID(1)))
        #expect(silent.refusal == "There is nothing there to project.")
        silent.project(nil)
        #expect(silent.refusal == "Click an edge or a face of the model to project it.")
    }

    /// A face pick can leave several edges out for different reasons, and with none projectable all of them are said, as they
    /// are when some project.
    @Test func everyReasonForLeavingEdgesOutIsSaidWhenNothingProjects() {
        let circle = "Edge 2 can't be projected: it is a circle that doesn't face the sketch plane."
        let perpendicular = "Edge 3 can't be projected: it is perpendicular to the sketch plane."
        let (model, host) = makeModel(skipped: [circle, perpendicular])
        model.project(.face(solid: 0, FaceID(1)))
        #expect(host.commits.isEmpty)
        #expect(model.refusal == "\(circle) \(perpendicular)")
    }

    @Test func someEdgesProjectingAndSomeNotStoresTheOnesThatDoAndSaysWhatWasLeftOut() {
        let reason = "Edge 2 can't be projected: it is a circle that doesn't face the sketch plane."
        let (model, host) = makeModel(answering: [candidate(0)], skipped: [reason])
        model.project(.face(solid: 0, FaceID(1)))
        #expect(host.commits.count == 1 && projected(model.sketch).count == 1)
        #expect(model.refusal == reason)
    }

    @Test func aProjectedEdgeHoldsAPointDrawnOnIt() {
        let (model, _) = makeModel(answering: [candidate(0)])
        model.project(.edge(solid: 0, EdgeID(1)))
        model.choose(.line)
        model.hover(at: Vector2(10, 0.3), tolerance: 1, modifiers: [])
        #expect(model.preview.inferred == [.pointOn], "S5b's point-on inference snaps onto projected geometry")
    }

    @Test func aSuspendedProjectionIsDrawnRed() {
        var sketch = Sketch()
        sketch.add(SketchEntity(.projected(ProjectionSource(reference: "edge1", curve: .line(.zero, Vector2(10, 0))))))
        sketch.add(SketchEntity(.projected(ProjectionSource(reference: "edge2", curve: .line(Vector2(0, 5), Vector2(10, 5)),
                                                            isSuspended: true))))
        let tints = SketchEditorModel(sketch: sketch, plane: .xy).overlay.lines.filter { $0.tint != .preview }.map(\.tint)
        #expect(tints == [.projected, .conflicting], "a projection whose pick finds no edge now is red, with its last curve")
    }

    @Test func projectHasItsKeyAndHint() {
        #expect(SketchTool.project.title == "Project" && SketchTool.project.key == "p")
        #expect(SketchTool.project.hint?.contains("edge") == true)
    }
}
