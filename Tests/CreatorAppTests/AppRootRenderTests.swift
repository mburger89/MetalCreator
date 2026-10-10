import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorStyle
import Foundation
import MetalUI
import MetalUIText
import Testing
@testable import CreatorApp
@testable import CreatorViewport

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

    @Test func theWindowDrawsWhileTheSaveChangesAlertIsUp() async throws {
        let app = await makeApp()
        try app.document.perform(.addNode(BuiltInNodes.registry.makeNode(NumberNode.typeID)))
        #expect(app.closeRequested() == .later)
        #expect(!render(app).glyphs.isEmpty, "the alert's buttons are built beside the window")
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

    /// Resizing the dock moves the triad (spec §6.3). Its letters (MetalUI text) and its lines (the GPU, at
    /// `TriadLayout.origin` in the surface) must move together: before and after each resize every axis letter is
    /// drawn where the renderer puts that axis' tip, and the surface's redraw value changes, because an on-demand
    /// `MetalView` repaints only then and would otherwise keep the triad's lines where they were.
    @Test(arguments: [(DockSide.bottom, 120.0), (.bottom, -120.0), (.left, 120.0), (.left, -120.0)])
    func theTriadsLettersStayOnItsAxesWhenTheDockResizes(_ dock: DockSide, _ translation: Double) async throws {
        let app = AppModel(kernel: FakeKernel(), file: GraphFile(graph: Graph(), viewState: ViewState(dock: dock)))
        await app.settle()
        try expectTriadLettersOnTheirAxes(app)
        let before = app.viewport.renderKey
        let layoutBefore = app.viewport.triadLayout
        app.beginPanelResize()
        app.resizePanel(by: translation)
        app.endPanelResize()
        await app.settle()
        #expect(app.viewport.triadLayout != layoutBefore, "the resize moved the triad")
        #expect(app.viewport.renderKey != before, "the surface redraws, so the triad's lines move too")
        try expectTriadLettersOnTheirAxes(app)
    }

    /// Every triad letter's glyph is centred where `TriadLayout` puts that axis' label in the surface's frame.
    func expectTriadLettersOnTheirAxes(_ app: AppModel, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let scale = 2.0
        let scene = render(app)
        let surface = try #require(scene.surfaces.first, sourceLocation: sourceLocation)
        let size = ViewportSize(width: Double(surface.bounds.size.width) / scale,
                                height: Double(surface.bounds.size.height) / scale)
        let triad = app.viewport.triadLayout
        let origin = triad.origin(in: size)
        let labels = app.viewport.triadLabels()
        #expect(labels.count >= 2, sourceLocation: sourceLocation)
        let centres = scene.glyphs.map { glyph in
            (x: Double(glyph.bounds.origin.x + glyph.bounds.size.width / 2) / scale,
             y: Double(glyph.bounds.origin.y + glyph.bounds.size.height / 2) / scale)
        }
        for label in labels {
            let expectedX = Double(surface.bounds.origin.x) / scale + origin.x + label.position.x
            let expectedY = Double(surface.bounds.origin.y) / scale + origin.y + label.position.y
            let nearest = centres.map { hypot($0.x - expectedX, $0.y - expectedY) }.min() ?? .infinity
            #expect(nearest < 6, "\(label.text) is drawn \(nearest) pt from its axis tip", sourceLocation: sourceLocation)
        }
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
