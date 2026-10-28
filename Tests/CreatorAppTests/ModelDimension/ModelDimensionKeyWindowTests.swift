import CreatorGeometry
import CreatorGraph
import CreatorNodes
import CreatorSketch
import CreatorViewport
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorEditor
@testable import CreatorSketchEditor
#if canImport(CreatorOCCT)
@testable import CreatorOCCT
#endif

/// DIM-4 Task 6: D starts the model dimension tool over the viewport, through the app's real window (the keymap, `AppInput`,
/// focus and the key regions); the face menu's Dimension starts it with that pick.
@MainActor
struct ModelDimensionKeyWindowTests {
    /// Above the graph panel with the default (bottom) dock: the viewport, not the canvas.
    let viewportSpot = Point(x: Pixels(700), y: Pixels(300))

    func open() async throws -> (app: AppWindow, rectangle: Node, canvasSpot: Point<Pixels>) {
        var builder = GraphBuilder()
        let part = builder.box(at: Vector2(40, 40))
        let app = try await AppWindow.open(builder.graph)
        return (app, part.rectangle, app.point(inCanvasView: Vector2(900, 120)))
    }

    @Test func dOverTheViewportStartsTheTool() async throws {
        let (app, _, _) = try await open()
        app.window.hover(at: viewportSpot)
        app.window.typeKey("d")
        try await app.window.runUntilIdle()
        #expect(app.model.modelDimension != nil)
        let prompt = ModelDimensionText.prompt(picked: 0)
        #expect(try !app.window.elements { $0.label == prompt || $0.value == prompt }.isEmpty, "the banner is shown")
    }

    @Test func dInAPanelFieldTypes() async throws {
        let (app, rectangle, _) = try await open()
        app.window.click(at: app.point(inCanvas: Vector2(60, 80)))
        #expect(app.editor.selection == [rectangle.id])
        let field = try #require(app.window.elements {
            $0.role == .textField && $0.frame.origin.x.value >= Float(app.inspectorColumnStart)
        }.first)
        try app.window.click(field)
        app.window.typeText("d")
        #expect(app.model.modelDimension == nil)
        #expect(try app.window.focusedElement?.value?.contains("d") == true, "the d landed in the field's text")
    }

    @Test func dInTheValueBoxTypes() async throws {
        var sketch = Sketch(plane: .fixed(.xy))
        let a = sketch.addPoint(Vector2(0, 0))
        let b = sketch.addPoint(Vector2(60, 0))
        let line = sketch.addLine(from: a, to: b)
        sketch.add(.fix(a, at: .zero))
        sketch.add(.horizontal(line))
        let dimension = sketch.addDimension(.length(line), value: 60)
        var builder = GraphBuilder()
        let box = builder.sketchedBox(sketch)
        let app = try await AppWindow.open(builder.graph)
        app.model.beginSketch(for: box.sketch.id)
        await app.model.settle()
        app.redraw()
        try #require(app.model.viewport.openValueBox(for: SketchDimensionDrawing.overlayID(dimension)))
        try await app.window.runUntilIdle()
        try #require(app.model.viewport.valueBox?.draft == "60")
        app.window.typeText("d")
        #expect(app.model.viewport.valueBox?.draft == "d", "the box selects its value, so the d replaces it")
        #expect(app.model.modelDimension == nil)
    }

    @Test func dOverTheGraphCanvasDoesNothing() async throws {
        let (app, _, canvasSpot) = try await open()
        let graph = app.editor.graph
        app.window.hover(at: canvasSpot)
        app.window.typeKey("d")
        #expect(app.model.modelDimension == nil)
        #expect(app.editor.graph == graph)
    }

    @Test func dInSketchModeChoosesTheSketchDimensionTool() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox(Sketch(plane: .fixed(.xy)))
        let app = try await AppWindow.open(builder.graph)
        app.model.beginSketch(for: box.sketch.id)
        await app.model.settle()
        app.window.hover(at: viewportSpot)
        app.window.typeKey("d")
        #expect(app.model.sketch?.editor.tool == .dimension)
        #expect(app.model.modelDimension == nil)
    }

    @Test func escapeCancelsTheTool() async throws {
        let (app, _, _) = try await open()
        app.window.hover(at: viewportSpot)
        app.window.typeKey("d")
        try await app.window.runUntilIdle()
        try #require(app.model.modelDimension != nil)
        app.window.typeKey(.escape)
        #expect(app.model.modelDimension == nil)
    }

    #if canImport(CreatorOCCT)
    @Test func theMenusDimensionStartsWithThatPick() async throws {
        let part = try await ModelDimensionToolTests().plate()
        let app = part.app
        app.viewport.choose(.dimension(try part.rim(0)))
        #expect(app.modelDimension?.pickedCount == 1)
    }
    #endif
}
