import CreatorGraph
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp

/// While a sketch is open the top bar holds the sketch toolbar, and the window is still dragged by its empty parts: the
/// label and the gap before Finish (gap M6-c, MetalUI C22). The tool buttons, Finish and the inspector are not handles.
@MainActor
struct SketchWindowDragWindowTests {
    func openSketch() async throws -> AppWindow {
        var builder = GraphBuilder()
        let box = builder.sketchedBox(rectangleSketch())
        let app = try await AppWindow.open(builder.graph)
        app.model.beginSketch(for: box.sketch.id)
        await app.model.settle()
        app.redraw()
        try #require(app.model.sketch != nil)
        return app
    }

    @Test func theToolbarsLabelGapAndStripMoveTheWindow() async throws {
        let app = try await openSketch()
        let label = try app.topBarLabel()
        #expect(app.windowDragRequests(draggingFrom: app.centre(of: label)) == 1, "the label")
        #expect(app.windowDragRequests(draggingFrom: app.point(1250, 34)) == 1, "the gap before Finish")
        #expect(app.windowDragRequests(draggingFrom: app.point(600, 5)) == 1, "the strip")
        // SketchChrome's backdrop (a drag gesture) starts at the glass, y = 12; the strip is drawn above it, so the
        // rest of the strip drags too, down to the row above where the controls start.
        #expect(app.windowDragRequests(draggingFrom: app.point(600, Float(AppLayout.margin) + 3)) == 1, "over the chrome's top padding")
        let lastRow = Float(AppLayout.windowDragStripHeight) - 1
        #expect(app.windowDragRequests(draggingFrom: app.point(600, lastRow)) == 1, "the strip's last row")
    }

    /// A window shorter than its panels need: the content overflows the bottom, and the top bar and the strip stay at the top
    /// (an overflowing root used to be centred in the window, which moved them up by half the overflow: the Windows suite's text,
    /// taller than CoreText's, overflowed a 900-point window by 6 points and the strip's last 3 rows ended above the controls).
    @Test func aWindowTooShortForItsPanelsKeepsTheTopBarAndTheStripAtTheTop() async throws {
        let app = try await openSketch()
        app.window.resize(to: Size(width: Pixels(1440), height: Pixels(300)))
        try await app.window.runUntilIdle()
        let bottom = Float(AppLayout.margin + AppLayout.topBarHeight)
        let buttons = try app.window.elements(where: { $0.role == .button && $0.frame.origin.y.value < bottom })
        let top = try #require(buttons.map(\.frame.origin.y.value).min())
        #expect(top >= Float(AppLayout.windowDragStripHeight), "the controls start below the strip")
        let lastRow = Float(AppLayout.windowDragStripHeight) - 1
        #expect(app.windowDragRequests(draggingFrom: app.point(600, lastRow)) == 1, "the strip's last row")
        #expect(app.windowDragRequests(draggingFrom: app.point(600, 0)) == 1, "the strip's first row")
    }

    @Test func noToolbarButtonMovesTheWindow() async throws {
        let app = try await openSketch()
        let controls = try app.topBarControls()
        #expect(controls.count >= 10, "the tools, Construction, Delete and Finish")
        for control in controls {
            #expect(app.windowDragRequests(draggingFrom: app.centre(of: control)) == 0, "\(control.label ?? "a control")")
        }
    }

    @Test func theInspectorsGlassIsNotAHandle() async throws {
        let app = try await openSketch()
        let inside = app.point(Float(app.inspectorColumnStart) + 5, 80)
        #expect(app.windowDragRequests(draggingFrom: inside) == 0)
    }
}
