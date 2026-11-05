import CreatorGraph
import CreatorKernel
import CreatorSketchEditor
import MetalUI
import Testing
@testable import CreatorApp

/// Every label of the sketch toolbar shows in full at the default window width (ui-polish finding 2): a truncated label
/// ("Dimensi…") draws fewer glyphs than its text has letters.
@MainActor
struct SketchToolbarFitTests {
    private func openSketch() async throws -> AppModel {
        var builder = GraphBuilder()
        let box = builder.sketchedBox(rectangleSketch())
        let app = AppModel(kernel: FakeKernel(), file: GraphFile(graph: builder.graph))
        await app.settle()
        app.beginSketch(for: box.sketch.id)
        await app.settle()
        return app
    }

    /// The size of every glyph the bar draws, in order. A label cut short ("Dimensi…") swaps letters for an ellipsis, so its
    /// sizes differ from the same bar drawn with room to spare.
    private func glyphSizes(_ app: AppModel, width: Double) -> [[Double]] {
        let bar = TopBar(model: app, clearance: Pixels(56))
        let scene = renderFrame({ ZStack { bar } }, size: Size(width: Pixels(Float(width)), height: Pixels(100)), scaleFactor: 2,
                                textSystem: testTextSystem(), atlas: GlyphAtlas(width: 1024, height: 1024))
        return scene.glyphs.map { [Double($0.bounds.size.width), Double($0.bounds.size.height)] }
    }

    /// The default window is 1440 pt wide and the bar has the window's 12 pt margin on both sides. The macOS traffic lights'
    /// clearance (about 56 pt) is in `TopBar`'s `clearance`. A narrower window (the minimum is 1000 pt) or SDL's 138 pt button
    /// cluster leaves less than the 14 tools need in one row, which is not covered here. Macs only: the portable text
    /// system's fonts on Linux and Windows are wider, and there the labels are cut short at this width (CI, human check UP-2).
    #if canImport(CoreText)
    @Test func everyLabelShowsInFullInTheDefaultWindow() async throws {
        let app = try await openSketch()
        let editor = try #require(app.sketch).editor
        let width = 1440.0 - 2 * AppLayout.margin
        // The widest state: both marks showing, on the longest tool title.
        editor.press(.arcThreePoint)
        editor.toggleConstruction()
        let roomy = glyphSizes(app, width: 4000)
        #expect(roomy.count > 100)
        #expect(glyphSizes(app, width: width) == roomy, "a label is cut short in the default window")
    }
    #endif
}
