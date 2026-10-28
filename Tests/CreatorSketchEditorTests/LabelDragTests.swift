import CreatorGeometry
import CreatorSketch
import CreatorViewport
import Testing
@testable import CreatorSketchEditor

/// Dragging a dimension's label (spec §4.3): the label follows the pointer on the plane with no solve, and the release is
/// one "Place Dimension" step when it moved.
@MainActor
struct LabelDragTests {
    /// A projector looking straight at XY, 1 pt per mm, centred on the origin.
    let projector = ViewportProjector(pose: CameraPose(target: .zero, distance: 100, pitch: .pi / 2, projection: .orthographic),
                                      size: ViewportSize(width: 400, height: 300))

    func screen(_ p: Vector2) throws -> ScreenPoint {
        try #require(projector.screenPoint(of: Plane.xy.point(p)))
    }

    func makeModel() -> (SketchEditorModel, RectangleSketch, RecordingHost) {
        let rectangle = RectangleSketch()
        let model = SketchEditorModel(sketch: rectangle.sketch, plane: .xy)
        return (model, rectangle, RecordingHost(model))
    }

    @Test func draggingALabelMovesItInOneStep() throws {
        let (model, rectangle, host) = makeModel()
        let id = SketchDimensionDrawing.overlayID(rectangle.width)
        let before = try #require(model.sketch.dimensions[rectangle.width])
        #expect(model.dragBegan(onDimension: id, at: try screen(Vector2(30, -5)), modifiers: [], projector: projector))
        model.dragMoved(to: try screen(Vector2(30, -10)), modifiers: [], projector: projector)
        model.dragMoved(to: try screen(Vector2(30, -15)), modifiers: [], projector: projector)
        #expect(host.commits.isEmpty, "nothing is stored while dragging")
        model.dragEnded(at: try screen(Vector2(30, -15)), modifiers: [], projector: projector)
        #expect(host.commits.map(\.name) == ["Place Dimension"])
        let after = try #require(model.sketch.dimensions[rectangle.width])
        let label = try #require(after.labelPoint)
        #expect((label - Vector2(30, -15)).length < 1e-6)
        #expect(after.kind == before.kind && after.value == before.value)
    }

    @Test func aDragThatMovesNothingIsNoStep() throws {
        let (model, rectangle, host) = makeModel()
        let id = SketchDimensionDrawing.overlayID(rectangle.width)
        let before = model.sketch
        let start = try screen(Vector2(30, -5))
        #expect(model.dragBegan(onDimension: id, at: start, modifiers: [], projector: projector))
        model.dragEnded(at: start, modifiers: [], projector: projector)
        #expect(host.commits.isEmpty)
        #expect(model.sketch == before)
    }

    @Test func aPendingDimensionsTextIsNotDragged() throws {
        let (model, _, _) = makeModel()
        #expect(!model.dragBegan(onDimension: SketchDimensionDrawing.pendingID, at: try screen(.zero), modifiers: [],
                                 projector: projector))
        model.choose(.dimension)
        model.click(at: Vector2(0.2, 0.2), tolerance: 1, modifiers: [])
        model.click(at: Vector2(60.2, 40.2), tolerance: 1, modifiers: [])
        try #require(model.pending != nil)
        let width = try #require(model.sketch.dimensionIDs.first)
        #expect(!model.dragBegan(onDimension: SketchDimensionDrawing.overlayID(width), at: try screen(.zero), modifiers: [],
                                 projector: projector), "nothing else is dragged while a dimension is pending")
    }

    @Test func aFeatureDimensionIsNotTheEditors() throws {
        let (model, _, _) = makeModel()
        #expect(!model.dragBegan(onDimension: OverlayDimensionID("feature/x"), at: try screen(.zero), modifiers: [],
                                 projector: projector))
    }

    @Test func itWorksInAnyTool() throws {
        let (model, rectangle, host) = makeModel()
        model.choose(.line)
        let id = SketchDimensionDrawing.overlayID(rectangle.height)
        #expect(model.dragBegan(onDimension: id, at: try screen(Vector2(70, 20)), modifiers: [], projector: projector))
        model.dragEnded(at: try screen(Vector2(80, 20)), modifiers: [], projector: projector)
        #expect(host.commits.map(\.name) == ["Place Dimension"])
    }
}
