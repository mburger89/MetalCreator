import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorViewport

/// The graph panel tells the editor where it is in the window itself (`EditorModel.panelPlacement`: its frame from
/// `onGeometryChange`, the window's size from the environment; gap EP-a), and `AppLayout`'s numbers say the same, so
/// the panel is drawn exactly where the layout puts it.
@MainActor
struct PanelPlacementTests {
    let window = Vector2(1400, 900)

    @Test(arguments: [DockSide.left, .bottom])
    func thePanelIsDrawnWhereTheLayoutSays(_ dock: DockSide) async throws {
        let app = AppModel(kernel: FakeKernel(), file: GraphFile(graph: Graph(), viewState: ViewState(dock: dock)))
        await app.settle()
        let frame = try #require(ExpectedLayout.graphPanelFrame(of: app, window: window))
        let input = AppInput(model: app)
        let scene = renderFrame({ ZStack { AppRoot(model: app, input: input) } },
                                size: Size(width: Pixels(1400), height: Pixels(900)), scaleFactor: 2,
                                textSystem: testTextSystem(), atlas: GlyphAtlas(width: 1024, height: 1024))
        let scale = 2.0
        let drawn = scene.rects.contains { rect in
            abs(Double(rect.bounds.origin.x) / scale - frame.origin.x) < 1
                && abs(Double(rect.bounds.origin.y) / scale - frame.origin.y) < 1
                && abs(Double(rect.bounds.size.width) / scale - frame.size.x) < 1
                && abs(Double(rect.bounds.size.height) / scale - frame.size.y) < 1
        }
        #expect(drawn, "no glass rect at \(frame)")
    }

    /// Decision D1: in the real window, headless, the property form of `AppModel.panelPlacement` is the measured panel,
    /// and it agrees with `AppLayout`'s numbers in both docks; the canvas is the panel less the library, the header and
    /// the refusal line.
    @Test(arguments: [DockSide.left, .bottom])
    func theEditorIsToldWhereItsCanvasIs(_ dock: DockSide) async throws {
        let app = try await AppWindow.open(dock: dock)
        let placement = try #require(app.model.panelPlacement, "measured with no draw and no setup")
        #expect(placement.window == app.size)
        let expected = try #require(ExpectedLayout.graphPanelFrame(of: app.model, window: app.size))
        #expect(placement.panel == expected)
        let local = GraphPanelLayout.canvasFrame(inPanelOf: expected.size, flow: app.editor.flow, showsLibrary: false,
                                                 showsRefusal: false)
        #expect(app.canvasFrame == CanvasRect(origin: expected.origin + local.origin, size: local.size))
        #expect(app.editor.panelPlacement == app.model.panelPlacement)
    }

    @Test func theLibraryMovesTheCanvasInTheMeasuredFrameToo() async throws {
        let app = try await AppWindow.open(dock: .left)
        let withoutLibrary = app.canvasFrame
        app.editor.toggleLibrary()
        try await app.window.runUntilIdle()
        let panel = try #require(app.model.panelPlacement).panel
        #expect(app.canvasFrame.origin == panel.origin + Vector2(10, 46 + 176 + 8), "under the library's strip")
        #expect(app.canvasFrame.size.y < withoutLibrary.size.y)
    }

    @Test func movingTheDockMovesThePlacement() async throws {
        let app = try await AppWindow.open(dock: .left)
        app.editor.setDock(.bottom)
        try await app.window.runUntilIdle()
        #expect(app.model.panelPlacement?.panel.origin == Vector2(12, 900 - 12 - app.model.panelHeight))
    }

    @Test func hidingThePanelClearsThePlacementAndShowingItBringsItBack() async throws {
        let app = try await AppWindow.open(dock: .bottom)
        app.editor.setDock(.hidden)
        try await app.window.runUntilIdle()
        #expect(app.model.panelPlacement == nil, "a hidden panel is nowhere")
        #expect(app.editor.canvasFrameInWindow == nil)
        app.editor.setDock(.bottom)
        try await app.window.runUntilIdle()
        #expect(app.model.panelPlacement != nil)
    }

    @Test func aNewDocumentIsPlacedToo() async throws {
        let app = try await AppWindow.open()
        let before = try #require(app.model.panelPlacement)
        app.model.load(GraphFile(), from: nil)
        try #require(app.editor.dock == .left, "set up: a new document docks left, so the panel moves")
        try await app.window.runUntilIdle()
        let expected = try #require(ExpectedLayout.graphPanelFrame(of: app.model, window: app.size))
        #expect(expected != before.panel)
        #expect(app.model.panelPlacement == PanelPlacement(window: app.size, panel: expected), "the new editor was told")
    }

    /// Resizing the window while it is open: the placement follows, and a window grown by far more than the culling
    /// margin in one step (full screen, the green zoom button) rebuilds the canvas with the node it uncovers.
    @Test func aGrownWindowRebuildsTheCanvasWithWhatItUncovers() async throws {
        var builder = GraphBuilder()
        let near = builder.box(at: CanvasFlow(.left).stored(Vector2(20, 20))).rectangle
        let far = builder.box(at: CanvasFlow(.left).stored(Vector2(20, 1200))).rectangle
        let app = try await AppWindow.open(builder.graph, dock: .left)
        #expect(app.editor.drawnNodes.contains { $0.id == near.id })
        #expect(!app.editor.drawnNodes.contains { $0.id == far.id }, "set up: the far node is culled")
        app.window.resize(to: Size(width: Pixels(1440), height: Pixels(1600)))
        try await app.window.runUntilIdle()
        #expect(app.model.panelPlacement?.window == Vector2(1440, 1600))
        let height = try #require(app.model.panelPlacement).panel.size.y
        #expect(height == 1520, "the left dock runs down the window")
        #expect(app.editor.drawnNodes.contains { $0.id == far.id }, "and draws the node it uncovers")
    }
}
