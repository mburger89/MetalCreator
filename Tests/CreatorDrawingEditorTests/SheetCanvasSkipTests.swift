import CreatorGeometry
import CreatorKernel
import MetalUI
import MetalUITesting
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// The canvas's layers are `.equatable()` (plan R27; MetalUI C14): a pan evaluates none of them, a selection change evaluates
/// the two views whose selection changed, and a view off screen is not built. Counted through `FrameWork`'s
/// `contentEvaluations` in a headless window, never in milliseconds.
@MainActor
@Suite("Sheet canvas content skipping")
struct SheetCanvasSkipTests {
    struct Fixture {
        var harness: EditorHarness
        var window: DrawingWindow
        var views: [DrawingView]
    }

    private func total(_ window: DrawingWindow) -> Int {
        window.window.frameWork.reduce(0) { $0 + $1.contentEvaluations }
    }

    /// A sheet with views at `centres` (A0 landscape, 1:1), each a 40 x 20 mm rectangle, shown at zoom 1.
    private func open(_ centres: [Vector2], zoom: Double = 1) async throws -> Fixture {
        let views = centres.map { EditorDocuments.view(at: $0) }
        let sheet = DrawingSheet(name: "Sheet 1", size: .a0, orientation: .landscape, views: views)
        let harness = EditorHarness(
            document: EditorDocuments.document([sheet]), sheet: sheet.id,
            contents: Dictionary(uniqueKeysWithValues: views.map { ($0.id, EditorHarness.rectangle(40, 20)) }))
        let window = try await DrawingWindow.open(scaleFactor: 2) { SheetCanvas(model: harness.model) }
        harness.model.transform = SheetTransform(offset: Vector2(10, 300 + 100 * zoom), zoom: zoom)
        window.redraw()
        try await window.window.runUntilIdle()
        return Fixture(harness: harness, window: window, views: views)
    }

    @Test func aPanSkipsEveryView() async throws {
        let f = try await open([Vector2(100, 100), Vector2(300, 100), Vector2(500, 100)])
        // The first frame after a change is redone by MetalUI: warm-up.
        f.harness.model.transform = SheetTransform(offset: Vector2(7, 400), zoom: 1)
        f.window.redraw()
        f.window.window.resetFrameWork()
        for step in 1...3 {
            f.harness.model.transform = SheetTransform(offset: Vector2(7 + Double(step) * 3, 400), zoom: 1)
            f.window.redraw()
        }
        #expect(total(f.window) == 0, "no layer evaluated during a pan")
    }

    @Test func aSelectionChangeRebuildsTwoViews() async throws {
        let f = try await open([Vector2(100, 100), Vector2(300, 100), Vector2(500, 100)])
        f.harness.model.selection = [f.views[0].id]
        f.window.redraw()
        f.window.redraw()
        f.window.window.resetFrameWork()
        f.harness.model.selection = [f.views[1].id]
        f.window.redraw()
        #expect(total(f.window) == 2, "the view that lost the selection and the one that gained it")
    }

    @Test func offscreenViewsAreNotBuilt() async throws {
        let onScreen = try await open([Vector2(100, 100), Vector2(200, 100), Vector2(300, 100)], zoom: 3)
        let cut = try await open([Vector2(100, 100), Vector2(450, 100), Vector2(500, 100)], zoom: 3)
        #expect(total(onScreen.window) - total(cut.window) == 4,
                "two views beyond the visible rectangle were skipped, a linework and an annotations layer each")
    }

    /// The dimension scene of `SelectionScene` shown in a window, zoomed and placed so its view is on screen.
    private func openDimensionScene() async throws -> (scene: SelectionScene, window: DrawingWindow) {
        let scene = SelectionScene.make([.horizontal])
        let window = try await DrawingWindow.open(scaleFactor: 2) { SheetCanvas(model: scene.h.model) }
        scene.h.model.transform = SheetTransform(offset: Vector2(0, 297 * 4), zoom: 4)
        window.redraw()
        try await window.window.runUntilIdle()
        return (scene, window)
    }

    @Test func aDimensionDragEvaluatesTwoLayers() async throws {
        let (s, window) = try await openDimensionScene()
        let model = s.h.model
        let start = s.centre(of: SelectionScene.horizontal) - Vector2(7, 0)
        model.primaryChanged(to: s.h.canvas(start.x, start.y), modifiers: [])
        window.redraw()
        window.redraw()
        for step in 1...3 {
            let point = start + Vector2(0, -Double(step) * 0.5)
            model.primaryChanged(to: s.h.canvas(point.x, point.y), modifiers: [])
            window.window.resetFrameWork()
            window.redraw()
            #expect(total(window) == 2, "step \(step): the view's annotation layer and the selection layer")
        }
        model.primaryEnded(at: s.h.canvas(start.x, start.y - 2), modifiers: [])
    }

    @Test func aZoomEvaluatesEveryLayer() async throws {
        let f = try await open([Vector2(100, 100), Vector2(300, 100)])
        f.harness.model.transform = SheetTransform(offset: Vector2(10, 400), zoom: 1.5)
        f.window.redraw()
        f.window.window.resetFrameWork()
        f.harness.model.transform = SheetTransform(offset: Vector2(10, 400), zoom: 2)
        f.window.redraw()
        // The frame layer, a linework and an annotations layer per view, and the selection layer: widths and dashes are in
        // screen units, so a zoom step rebuilds all of them (drawings speed R6).
        #expect(total(f.window) == 1 + 2 * f.views.count + 1)
    }

    @Test func aPickAfterADragHitsTheRightStroke() throws {
        let s = SelectionScene.make([.horizontal])
        let model = s.h.model
        let edge = try #require(model.picture?.strokes.firstIndex { $0.view == s.view.id && $0.annotation == nil && $0.source != nil })
        let stroke = try #require(model.picture?.strokes[edge])
        let point = stroke.bounds.center
        func hovered() -> SheetStroke? {
            model.pointerMoved(to: s.h.canvas(point.x, point.y))
            return model.hoveredStroke.flatMap { model.picture?.strokes[$0] }
        }
        let before = try #require(hovered())
        let start = s.centre(of: SelectionScene.horizontal) - Vector2(7, 0)
        model.primaryChanged(to: s.h.canvas(start.x, start.y), modifiers: [])
        for step in 1...4 {
            let moved = start + Vector2(0, -Double(step) * 0.5)
            model.primaryChanged(to: s.h.canvas(moved.x, moved.y), modifiers: [])
        }
        model.primaryEnded(at: s.h.canvas(start.x, start.y - 2), modifiers: [])
        #expect(hovered() == before, "the same projected edge is under the pointer after the drag")
    }
}
