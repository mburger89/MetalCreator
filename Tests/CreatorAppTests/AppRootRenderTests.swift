import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorStyle
import MetalUI
import MetalUIText
import Testing
@testable import CreatorApp

/// Headless frames of the whole window. They don't compare pixels: they prove the shell builds, lays out and
/// paints in every dock, with a pick in progress, and that the panels are laid out to `AppLayout`'s numbers (the
/// viewport's model area depends on them). Looks are human checks (group M6).
@MainActor
struct AppRootRenderTests {
    func render(_ app: AppModel) -> Scene {
        let input = AppInput(model: app)
        return renderFrame({ ZStack { AppRoot(model: app, input: input) } }, size: Size(width: Pixels(1400), height: Pixels(900)),
                           scaleFactor: 2, textSystem: CoreTextTextSystem(), atlas: GlyphAtlas(width: 1024, height: 1024))
    }

    @Test(arguments: [DockSide.left, .bottom, .hidden])
    func theWindowDrawsInEveryDock(_ dock: DockSide) async {
        var builder = GraphBuilder()
        _ = builder.box()
        let app = AppModel(kernel: FakeKernel(), file: GraphFile(graph: builder.graph, viewState: ViewState(dock: dock)))
        await app.settle()
        let scene = render(app)
        #expect(scene.surfaces.count == 1, "the viewport's Metal surface")
        #expect(!scene.glyphs.isEmpty)
    }

    @Test func theDockedPanelIsLaidOutToTheModelsWidth() async {
        let app = await makeApp()
        app.beginPanelResize()
        app.resizePanel(by: 120)
        app.endPanelResize()
        let scene = render(app)
        // The graph panel's glass is the widest rect starting at the margin, below the top bar.
        let scale = 2.0
        let panels = scene.rects.filter { rect in
            abs(Double(rect.bounds.origin.x) - AppLayout.margin * scale) < 1
                && Double(rect.bounds.origin.y) > (AppLayout.margin + AppLayout.topBarHeight) * scale
        }
        let widest = panels.map { Double($0.bounds.size.width) / scale }.max() ?? 0
        #expect(abs(widest - app.panelWidth) < 1, "drawn \(widest) pt wide for a \(app.panelWidth) pt panel")
    }

    @Test func aPickInProgressDrawsItsBanner() async throws {
        var builder = GraphBuilder()
        let box = builder.box()
        let rule = builder.add(EdgesByTagNode.self)
        builder.wire(box.extrude, "solid", to: rule, "solid")
        let app = await makeApp(builder.graph)
        let before = render(app).glyphs.count
        app.beginPick(for: rule.id)
        await app.settle()
        #expect(app.pick != nil)
        #expect(render(app).glyphs.count > before, "the banner's text and buttons")
    }

    /// The whole window draws the app's theme (spec §6.6): after View ▸ Theme ▸ Alucard every panel paints exactly
    /// as a window that started in Alucard, and the viewport has it too.
    @Test func theWindowRepaintsInTheChosenTheme() async {
        func fills(_ scene: Scene) -> [[Float]] {
            scene.rects.map { [$0.background.h, $0.background.s, $0.background.l, $0.background.a] }
                + scene.glyphs.map { [$0.color.h, $0.color.s, $0.color.l, $0.color.a] }
        }
        let app = await makeApp()
        let dracula = fills(render(app))
        app.themes.select("alucard")
        await app.settle()
        let switched = fills(render(app))
        #expect(switched != dracula)
        #expect(app.viewport.theme == .alucard)
        let alucard = AppModel(kernel: FakeKernel(), themes: ThemeStore(preferences: InMemoryThemePreferences(selectedThemeID: "alucard")))
        await alucard.settle()
        #expect(switched == fills(render(alucard)))
    }
}
