import CreatorGraph
import CreatorKernel
import CreatorNodes
import MetalUI
import MetalUIText
import Testing
@testable import CreatorApp

/// `TopBar` starts its content in by the clearance it is given, in the bar and in the sketch toolbar's branch (spec
/// §6.1, gap M6-c). The window's real insets can't be set from outside MetalUI (`internal(set)`), so the clearance is
/// passed in; that `AppRoot` passes `AppLayout.topBarClearance` of the window's insets is human check AS-5.
@MainActor
struct TopBarClearanceRenderTests {
    /// The left edge, in points, of the leftmost glyph a top bar with this clearance draws.
    func firstGlyphX(_ app: AppModel, clearance: Double) -> Double {
        let scale = 2.0
        let bar = TopBar(model: app, clearance: Pixels(Float(clearance)))
        let scene = renderFrame({ ZStack { bar } }, size: Size(width: Pixels(1400), height: Pixels(100)), scaleFactor: 2,
                                textSystem: CoreTextTextSystem(), atlas: GlyphAtlas(width: 1024, height: 1024))
        return scene.glyphs.map { Double($0.bounds.origin.x) / scale }.min() ?? .nan
    }

    @Test func theBarsNameStartsInByTheClearance() async {
        let app = await makeApp()
        let flush = firstGlyphX(app, clearance: 0)
        #expect(flush.isFinite)
        #expect(abs(firstGlyphX(app, clearance: 69) - flush - 69) < 1, "the whole row moves right by the clearance")
    }

    @Test func theSketchToolbarStartsInByTheClearanceToo() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox(rectangleSketch())
        let app = AppModel(kernel: FakeKernel(), file: GraphFile(graph: builder.graph))
        await app.settle()
        app.beginSketch(for: box.sketch.id)
        await app.settle()
        #expect(app.sketch != nil)
        let flush = firstGlyphX(app, clearance: 0)
        #expect(flush.isFinite)
        #expect(abs(firstGlyphX(app, clearance: 69) - flush - 69) < 1)
    }
}
