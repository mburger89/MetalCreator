#if canImport(Metal)
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorStyle
import MetalUI
import Testing
@testable import CreatorApp

/// The window's glass panels blur the viewport (gap C10-a, adopted with MetalUI C21): each panel is one material record
/// painted after the viewport's GPU surface, so the blur sees it. The blur itself is MetalUI's (its `BackdropRenderTests`
/// read it back over a surface); what a person sees over a moving viewport is human check C21-1.
@MainActor
struct GlassBlursViewportTests {
    func scene(_ app: AppModel, themeEditor: ThemeEditorModel? = nil) -> Scene {
        let input = AppInput(model: app)
        return renderFrame({
            ZStack {
                if let themeEditor {
                    AppWindowRoot(model: app, input: input, themeEditor: themeEditor)
                } else {
                    AppRoot(model: app, input: input)
                }
            }
        }, size: Size(width: Pixels(1400), height: Pixels(900)), scaleFactor: 2, textSystem: testTextSystem(),
           atlas: GlyphAtlas(width: 1024, height: 1024))
    }

    /// Fails unless every backdrop record is painted after the viewport's surface.
    func expectEveryBlurSeesTheViewport(_ scene: Scene, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let surface = try #require(paintPosition(of: .surface, at: 0, in: scene), sourceLocation: sourceLocation)
        for index in scene.backdrops.indices {
            let blur = try #require(paintPosition(of: .backdrop, at: index, in: scene), sourceLocation: sourceLocation)
            #expect(blur > surface, "panel \(index) is painted before the viewport it should blur", sourceLocation: sourceLocation)
        }
    }

    @Test func theTopBarTheGraphPanelAndTheInspectorEachBlurTheViewport() async throws {
        let scene = scene(await makeApp())
        #expect(scene.backdrops.count == 3, "the top bar, the graph panel and the inspector")
        try expectEveryBlurSeesTheViewport(scene)
    }

    @Test func aPickBannerBlursTheViewportToo() async throws {
        var builder = GraphBuilder()
        let box = builder.box()
        let rule = builder.add(EdgesByTagNode.self)
        builder.wire(box.extrude, "solid", to: rule, "solid")
        let app = await makeApp(builder.graph)
        let before = scene(app).backdrops.count
        app.beginPick(for: rule.id)
        await app.settle()
        let picking = scene(app)
        #expect(picking.backdrops.count == before + 1)
        try expectEveryBlurSeesTheViewport(picking)
    }

    @Test func theThemeEditorBlursWhatIsBeneathIt() async throws {
        let app = await makeApp()
        let editor = ThemeEditorModel(themes: app.themes)
        let closed = scene(app, themeEditor: editor).backdrops.count
        editor.open()
        let open = scene(app, themeEditor: editor)
        #expect(open.backdrops.count == closed + 1)
        try expectEveryBlurSeesTheViewport(open)
    }

    @Test func theSketchToolbarAndInspectorBlurToo() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox(rectangleSketch(exposed: true))
        let app = await makeApp(builder.graph)
        let before = scene(app).backdrops.count
        app.beginSketch(for: box.sketch.id)
        await app.settle()
        #expect(app.sketch != nil)
        let sketching = scene(app)
        #expect(sketching.backdrops.count == before, "the sketch toolbar and inspector take the top bar's and inspector's places")
        try expectEveryBlurSeesTheViewport(sketching)
    }
}
#endif
