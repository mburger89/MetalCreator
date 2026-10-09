import CreatorGraph
import CreatorKernel
import CreatorNodes
import MetalUI
import MetalUIText
import Testing
@testable import CreatorApp

/// Headless frames of the window in sketch mode: the top bar holds the sketch toolbar and the inspector the sketch's
/// lists, in every dock. Looks, keys and the chrome's opacity to the pointer are human checks (group S5).
@MainActor
struct SketchModeRenderTests {
    @Test(arguments: [DockSide.left, .bottom, .hidden])
    func theWindowDrawsInSketchMode(_ dock: DockSide) async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox(rectangleSketch(exposed: true))
        let app = AppModel(kernel: FakeKernel(), file: GraphFile(graph: builder.graph, viewState: ViewState(dock: dock)))
        await app.settle()
        app.beginSketch(for: box.sketch.id)
        await app.settle()
        #expect(app.sketch != nil)
        let input = AppInput(model: app)
        let scene = renderFrame({ ZStack { AppRoot(model: app, input: input) } }, size: Size(width: Pixels(1400), height: Pixels(900)),
                                scaleFactor: 2, textSystem: CoreTextTextSystem(), atlas: GlyphAtlas(width: 1024, height: 1024))
        #expect(scene.surfaces.count == 1, "the viewport's Metal surface")
        #expect(!scene.glyphs.isEmpty)
    }

    /// The top bar and the inspector swap their views in sketch mode, and back when it ends: each draws other text
    /// (the toolbar's buttons for the document's name and menus; the sketch's lists for the node's rows).
    @Test func theTopBarAndTheInspectorSwapInTheSketchViews() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox(rectangleSketch(exposed: true))
        let app = AppModel(kernel: FakeKernel(), file: GraphFile(graph: builder.graph))
        await app.settle()
        app.editor.selection = [box.sketch.id]
        let before = (bar: glyphCount { TopBar(model: app) }, inspector: glyphCount { InspectorDock(model: app) })
        app.beginSketch(for: box.sketch.id)
        await app.settle()
        #expect(glyphCount { TopBar(model: app) } != before.bar)
        #expect(glyphCount { InspectorDock(model: app) } != before.inspector)
        app.finishSketch()
        #expect(glyphCount { TopBar(model: app) } == before.bar)
        #expect(glyphCount { InspectorDock(model: app) } == before.inspector)
    }

    func glyphCount<View: ElementGroup>(_ view: () -> View) -> Int {
        let content = view()
        return renderFrame({ ZStack { content } }, size: Size(width: Pixels(1400), height: Pixels(900)), scaleFactor: 2,
                           textSystem: CoreTextTextSystem(), atlas: GlyphAtlas(width: 1024, height: 1024)).glyphs.count
    }
}
