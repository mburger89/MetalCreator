import CreatorGeometry
import CreatorGraph
import CreatorSketch
import CreatorViewport
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorSketchEditor

/// Editing a sketch dimension in the view through the app's real window (spec §7): the box opens on the dimension's text, typing
/// changes nothing, Return commits one "Change Dimension" step, and Esc or a press elsewhere closes it with no change.
@MainActor
struct DimensionValueBoxWindowTests {
    /// One 60 mm line on XY with its length dimension.
    func lineSketch() -> (sketch: Sketch, dimension: DimensionID) {
        var sketch = Sketch(plane: .fixed(.xy))
        let a = sketch.addPoint(Vector2(0, 0))
        let b = sketch.addPoint(Vector2(60, 0))
        let line = sketch.addLine(from: a, to: b)
        sketch.add(.fix(a, at: .zero))
        sketch.add(.horizontal(line))
        let dimension = sketch.addDimension(.length(line), value: 60)
        return (sketch, dimension)
    }

    /// The window with the sketch open and the box open on its dimension, with the first frame after it drawn.
    func openBox() async throws -> (app: AppWindow, id: OverlayDimensionID) {
        let (sketch, dimension) = lineSketch()
        var builder = GraphBuilder()
        let box = builder.sketchedBox(sketch)
        let app = try await AppWindow.open(builder.graph)
        app.model.beginSketch(for: box.sketch.id)
        await app.model.settle()
        app.redraw()
        let id = SketchDimensionDrawing.overlayID(dimension)
        try #require(app.model.viewport.openValueBox(for: id))
        try await app.window.runUntilIdle()
        return (app, id)
    }

    /// Waits for the box's commit (Return starts it in a task) to be answered.
    func answered(_ app: AppWindow) async {
        for _ in 0..<200 where app.model.viewport.valueBox != nil { await Task.yield() }
        await app.model.settle()
    }

    @Test func typingChangesNoDocument() async throws {
        let (app, _) = try await openBox()
        let before = app.model.document.content
        app.window.typeText("7")
        app.window.typeText("0")
        #expect(app.model.viewport.valueBox?.draft == "70")
        #expect(app.model.document.content == before)
        #expect(app.model.document.undoName == nil)
    }

    @Test func returnCommitsOneStepAndTheCameraStays() async throws {
        let (app, id) = try await openBox()
        let pose = app.model.viewport.pose
        app.window.typeText("70")
        app.window.typeKey(.return)
        await answered(app)
        #expect(app.model.viewport.valueBox == nil)
        #expect(app.model.undoTitle == "Undo Change Dimension")
        #expect(app.model.viewport.pose == pose)
        let editor = try #require(app.model.sketch?.editor)
        let dimension = try #require(SketchDimensionDrawing.dimensionID(from: id))
        #expect(editor.sketch.dimensions[dimension]?.value == 70)
        app.model.document.undo()
        #expect(!app.model.document.canUndo, "one step")
    }

    @Test func escapeCancels() async throws {
        let (app, _) = try await openBox()
        app.window.typeText("70")
        app.window.typeKey(.escape)
        #expect(app.model.viewport.valueBox == nil)
        #expect(app.model.document.undoName == nil)
        #expect(app.model.sketch != nil, "Esc closed the box, not the sketch")
    }

    @Test func aPressOnTheViewportCancels() async throws {
        let (app, _) = try await openBox()
        app.window.typeText("70")
        app.window.click(at: Point(x: Pixels(700), y: Pixels(300)))
        #expect(app.model.viewport.valueBox == nil)
        #expect(app.model.document.undoName == nil)
    }

    @Test func theViewportsAndToolbarsKeysTypeIntoTheBox() async throws {
        let (app, _) = try await openBox()
        let pose = app.model.viewport.pose
        let tool = try #require(app.model.sketch?.editor.tool)
        app.window.typeText("F")
        app.window.typeText("c")
        #expect(app.model.viewport.valueBox?.draft == "Fc")
        #expect(app.model.viewport.pose == pose, "no framing")
        #expect(app.model.sketch?.editor.tool == tool, "the tool is unchanged")
    }

    @Test func finishingTheSketchClosesTheBox() async throws {
        let (app, _) = try await openBox()
        app.window.typeText("70")
        app.model.finishSketch()
        await app.model.settle()
        #expect(app.model.viewport.valueBox == nil)
        #expect(app.model.document.undoName == nil, "nothing was committed")
    }
}
