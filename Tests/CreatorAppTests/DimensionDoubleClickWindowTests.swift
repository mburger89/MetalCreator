import CreatorGeometry
import CreatorGraph
import CreatorSketch
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorSketchEditor
@testable import CreatorViewport

/// A double click on a dimension's text in the viewport, through the app's real window: the count is the platform's (MetalUI
/// `SpatialTapGesture.Value.clickCount`, gap DIM-a), so the viewport needs no timer of its own. `TestWindow.doubleClick(at:)`
/// sends the second press with click count 2, as AppKit does. The viewport fills the window, so its points are the window's.
@MainActor
struct DimensionDoubleClickWindowTests {
    /// The window with a sketch open that holds one 60 mm line and its length dimension, and the window point of the text's centre.
    func open() async throws -> (app: AppWindow, id: OverlayDimensionID, centre: Point<Pixels>) {
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
        await app.model.viewport.waitForAnimation()
        app.redraw()
        try await app.window.runUntilIdle()
        let id = SketchDimensionDrawing.overlayID(dimension)
        let placed = try #require(app.model.viewport.drawnDimensions.first { $0.id == id })
        let centre = app.windowPoint(Vector2(placed.textOrigin.x + placed.textSize.width / 2,
                                             placed.textOrigin.y + placed.textSize.height / 2))
        return (app, id, centre)
    }

    @Test func aDoubleClickOnADimensionsTextOpensItsBox() async throws {
        let (app, id, centre) = try await open()
        #expect(app.model.viewport.valueBox == nil)
        app.window.doubleClick(at: centre)
        #expect(app.model.viewport.valueBox?.id == id)
    }

    @Test func aSingleClickDoesNot() async throws {
        let (app, _, centre) = try await open()
        app.window.click(at: centre)
        #expect(app.model.viewport.valueBox == nil)
    }
}
