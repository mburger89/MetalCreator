import CreatorGeometry
import CreatorGraph
import CreatorNodes
import CreatorViewport
import Testing
@testable import CreatorApp

/// The cut view (implicit spec §5.1) over 7b's slice pose.
@MainActor
struct CutViewModelTests {
    static let bounds = BoundingBox(min: Vector3(-5, -10, 0), max: Vector3(5, 10, 30))
    static let above = Vector3(0.3, 0.2, 1).normalized ?? .unitZ

    @Test func itStartsOffWithNothingToDraw() {
        let model = CutViewModel()
        #expect(!model.isOn && model.pose == nil && model.clip == nil && model.handle == nil)
        model.turnOn(bounds: nil, toEye: Self.above)
        #expect(!model.isOn, "nothing in the scene, nothing to cut")
    }

    @Test func switchedOnItCutsTheNearSideOfTheAxisPlaneNearestTheView() throws {
        let model = CutViewModel()
        model.turnOn(bounds: Self.bounds, toEye: Self.above)
        #expect(model.isOn && model.axis == .xy)
        let clip = try #require(model.clip)
        #expect(clip.origin == Vector3(0, 0, 15) && clip.normal == .unitZ, "the box's middle, the side facing the viewer cut")
        #expect(clip.removes(Vector3(0, 0, 25)) && !clip.removes(Vector3(0, 0, 5)))
        let front = CutViewModel()
        front.turnOn(bounds: Self.bounds, toEye: Vector3(0.1, -1, 0.2))
        let frontClip = try #require(front.clip)
        #expect(front.axis == .xz && frontClip.normal.dot(Vector3(0.1, -1, 0.2)) > 0, "the cut side is the one facing the viewer")
        let behind = CutViewModel()
        behind.turnOn(bounds: Self.bounds, toEye: Vector3(0, 0.1, -1))
        #expect(try #require(behind.clip).normal.dot(Vector3(0, 0.1, -1)) > 0)
    }

    @Test func theHandleIsTheSlicesAndMovesThePlaneAlongItsNormal() throws {
        let model = CutViewModel()
        model.turnOn(bounds: Self.bounds, toEye: Self.above)
        let handle = try #require(model.handle)
        #expect(handle.id == CutViewModel.handleID && handle.direction == .unitZ && handle.value == 0)
        #expect(handle.range == -30...30 || handle.range.upperBound >= 15, "it reaches every corner of the box")
        model.move(to: 7)
        #expect(model.offset == 7 && model.clip?.origin == Vector3(0, 0, 22) && model.handle?.value == 7)
        model.move(to: 1_000)
        #expect(model.offset == handle.range.upperBound, "held to the limit")
        model.move(to: .nan)
        #expect(model.offset == handle.range.upperBound)
    }

    @Test func flippingCutsTheOtherSideAndSwitchingOffForgetsEverything() throws {
        let model = CutViewModel()
        model.turnOn(bounds: Self.bounds, toEye: Self.above)
        model.flip()
        #expect(model.clip?.normal == -Vector3.unitZ && model.isFlipped)
        let revision = model.revision
        model.turnOff()
        #expect(!model.isOn && model.clip == nil && model.handle == nil && model.revision == revision + 1)
        model.flip()
        model.move(to: 3)
        #expect(!model.isOn && model.revision == revision + 1, "nothing happens while off")
        model.turnOn(bounds: Self.bounds, toEye: Self.above)
        #expect(!model.isFlipped && model.offset == 0, "a new cut starts over")
    }

    @Test func thePlaneFollowsThePartsBox() throws {
        let model = CutViewModel()
        model.turnOn(bounds: Self.bounds, toEye: Self.above)
        let revision = model.revision
        model.follow(bounds: Self.bounds)
        #expect(model.revision == revision, "the same box changes nothing")
        model.follow(bounds: BoundingBox(min: .zero, max: Vector3(10, 10, 100)))
        #expect(model.clip?.origin == Vector3(5, 5, 50) && model.revision == revision + 1)
        model.follow(bounds: nil)
        #expect(model.clip?.origin == Vector3(5, 5, 50), "an empty scene keeps the last box")
    }

    @Test func theAppCutsTheViewportAndShowsTheHandle() async throws {
        var builder = GraphBuilder()
        _ = builder.box()
        let app = await makeApp(builder.graph)
        #expect(app.viewport.clip == nil && !app.viewport.handles.contains { $0.id == CutViewModel.handleID })
        app.setCutView(true)
        #expect(app.cutView.isOn && app.viewport.clip != nil)
        #expect(app.viewport.handles.contains { $0.id == CutViewModel.handleID })
        app.handleChanged(CutViewModel.handleID, 2, .ended)
        #expect(app.cutView.offset == 2 && !app.document.canUndo, "view state: no undo step")
        app.setCutView(false)
        #expect(app.viewport.clip == nil && !app.viewport.handles.contains { $0.id == CutViewModel.handleID })
        app.setCutView(true)
        app.load(GraphFile(graph: builder.graph), from: nil)
        #expect(!app.cutView.isOn && app.viewport.clip == nil, "a new document starts uncut")
    }

    @Test func anEmptyDocumentStaysUncut() async {
        let app = await makeApp()
        app.setCutView(true)
        #expect(!app.cutView.isOn && app.viewport.clip == nil)
    }
}
