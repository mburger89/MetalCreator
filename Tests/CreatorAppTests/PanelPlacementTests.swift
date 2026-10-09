import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import MetalUI
import MetalUIText
import Testing
@testable import CreatorApp
@testable import CreatorViewport

/// The app tells the editor where the graph panel is in the window (`AppLayout.graphPanelFrame`, the window's
/// size from the viewport, which fills it), and draws the panel exactly there.
@MainActor
struct PanelPlacementTests {
    let window = Vector2(1400, 900)

    @Test(arguments: [DockSide.left, .bottom])
    func thePanelIsDrawnWhereTheLayoutSays(_ dock: DockSide) async throws {
        let app = AppModel(kernel: FakeKernel(), file: GraphFile(graph: Graph(), viewState: ViewState(dock: dock)))
        await app.settle()
        let frame = try #require(AppLayout.graphPanelFrame(dock: dock, panelWidth: app.panelWidth,
                                                           panelHeight: app.panelHeight, window: window))
        let input = AppInput(model: app)
        let scene = renderFrame({ ZStack { AppRoot(model: app, input: input) } },
                                size: Size(width: Pixels(1400), height: Pixels(900)), scaleFactor: 2,
                                textSystem: CoreTextTextSystem(), atlas: GlyphAtlas(width: 1024, height: 1024))
        let scale = 2.0
        let drawn = scene.rects.contains { rect in
            abs(Double(rect.bounds.origin.x) / scale - frame.origin.x) < 1
                && abs(Double(rect.bounds.origin.y) / scale - frame.origin.y) < 1
                && abs(Double(rect.bounds.size.width) / scale - frame.size.x) < 1
                && abs(Double(rect.bounds.size.height) / scale - frame.size.y) < 1
        }
        #expect(drawn, "no glass rect at \(frame)")
    }

    @Test func theEditorIsToldWhereItsCanvasIs() async throws {
        let app = await makeApp()
        #expect(app.editor.panelPlacement == nil, "the window has no size before the viewport's first draw")
        app.viewport.recordViewSize(ViewportSize(width: window.x, height: window.y))
        let panel = try #require(AppLayout.graphPanelFrame(dock: .left, panelWidth: app.panelWidth,
                                                           panelHeight: app.panelHeight, window: window))
        #expect(app.editor.panelPlacement == PanelPlacement(window: window, panel: panel))
        #expect(app.editor.canvasFrameInWindow?.origin == panel.origin + Vector2(10, 46))
        app.editor.setDock(.bottom)
        #expect(app.editor.panelPlacement?.panel.origin == Vector2(12, 900 - 12 - app.panelHeight))
    }

    @Test func aNewDocumentIsPlacedToo() async {
        let app = await makeApp()
        app.load(GraphFile(), from: nil)
        app.viewport.recordViewSize(ViewportSize(width: window.x, height: window.y))
        #expect(app.editor.panelPlacement != nil)
    }
}
