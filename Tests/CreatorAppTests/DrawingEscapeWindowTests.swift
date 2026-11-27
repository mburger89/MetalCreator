import CreatorDrawingEditor
import CreatorGeometry
import CreatorGraph
import CreatorOCCT
import CreatorNodes
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp

/// Esc over the drawing sheet runs the drawing editor's `escapePressed` (back to Select), through the app's real window: the
/// keymap, `AppInput`, the button shortcuts and the sheet's key region.
@MainActor
struct DrawingEscapeWindowTests {
    func open() async throws -> AppWindow {
        let app = try await AppWindow.open()
        app.model.setMode(.drawing)
        app.model.drawing.editor.addSheet()
        await app.model.settle()
        app.redraw()
        try await app.window.runUntilIdle()
        return app
    }

    @Test(arguments: [DrawingTool.dimension, .baseView])
    func escOverTheSheetReturnsAToolToSelect(tool: DrawingTool) async throws {
        let app = try await open()
        let editor = app.model.drawing.editor
        editor.press(tool)
        #expect(editor.tool == tool)
        app.window.hover(at: Point(x: Pixels(700), y: Pixels(300)))
        app.window.typeKey(.escape)
        #expect(editor.tool == .select)
    }

    /// The graph's own Esc (clear the selection) must not take the key while the sheet is shown: the bracket's graph has nodes
    /// selected when a person switches to Drawing.
    @Test(arguments: [DrawingTool.dimension, .baseView])
    func escWithAGraphSelectionReturnsAToolToSelect(tool: DrawingTool) async throws {
        var builder = GraphBuilder()
        let part = builder.box(at: Vector2(40, 40))
        let app = try await AppWindow.open(builder.graph)
        app.editor.selection = [part.rectangle.id]
        app.model.setMode(.drawing)
        app.model.drawing.editor.addSheet()
        await app.model.settle()
        app.redraw()
        try await app.window.runUntilIdle()
        let editor = app.model.drawing.editor
        editor.press(tool)
        app.window.hover(at: Point(x: Pixels(700), y: Pixels(300)))
        app.window.typeKey(.escape)
        #expect(editor.tool == .select)
        #expect(app.editor.selection == [part.rectangle.id], "the graph's selection is not the sheet's to clear")
    }

    /// The tool is chosen with a click on its toolbar button, as a person does; the pointer then goes over the sheet.
    @Test func escAfterAToolbarClickReturnsTheToolToSelect() async throws {
        let app = try await open()
        let editor = app.model.drawing.editor
        let button = try app.window.element(label: "Base View")
        try app.window.click(button)
        #expect(editor.tool == .baseView)
        app.window.hover(at: Point(x: Pixels(700), y: Pixels(300)))
        app.window.typeKey(.escape)
        #expect(editor.tool == .select)
    }

    @Test func escOnTheBracketWithAViewReturnsTheToolToSelect() async throws {
        let app = try await AppWindow.open(kernel: OCCTKernel())
        try app.model.open(BracketExampleTests.file)
        await app.model.settle()
        app.model.setMode(.drawing)
        app.model.drawing.editor.addSheet()
        await app.model.settle()
        _ = await app.model.placeBaseView()
        app.redraw()
        try await app.window.runUntilIdle()
        let editor = app.model.drawing.editor
        editor.press(.dimension)
        for spot in [Point(x: Pixels(700), y: Pixels(300)), Point(x: Pixels(500), y: Pixels(400)), Point(x: Pixels(900), y: Pixels(500))] {
            editor.press(.dimension)
            app.window.hover(at: spot)
            app.window.typeKey(.escape)
            #expect(editor.tool == .select, "at \(spot)")
        }
    }

    @Test func escAfterPlacingADimensionWithDReturnsTheToolToSelect() async throws {
        let app = try await AppWindow.open(kernel: OCCTKernel())
        try app.model.open(BracketExampleTests.file)
        await app.model.settle()
        app.model.setMode(.drawing)
        app.model.drawing.editor.addSheet()
        await app.model.settle()
        let view = try #require(await app.model.placeBaseView())
        app.redraw()
        try await app.window.runUntilIdle()
        let editor = app.model.drawing.editor
        app.window.hover(at: Point(x: Pixels(700), y: Pixels(300)))
        app.window.typeKey("d")
        #expect(editor.tool == .dimension)
        _ = try #require(await app.model.dimensionBottomEdge(of: view))
        app.redraw()
        try await app.window.runUntilIdle()
        app.window.typeKey(.escape)
        #expect(editor.tool == .select)
    }

    @Test func escAfterChoosingAToolFromTheMoreMenu() async throws {
        let app = try await open()
        let editor = app.model.drawing.editor
        let more = try app.window.element(label: "More")
        try app.window.click(more)
        try app.window.chooseMenuItem("Dimension")
        #expect(editor.tool == .dimension)
        app.window.hover(at: Point(x: Pixels(700), y: Pixels(300)))
        app.window.typeKey(.escape)
        #expect(editor.tool == .select)
    }
}
