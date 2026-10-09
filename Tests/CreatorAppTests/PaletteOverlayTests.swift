import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import MetalUI
import MetalUIText
import Testing
@testable import CreatorApp
@testable import CreatorViewport

/// The add-node palette floats over the whole window (spec §6.2): with the panel docked at the bottom it opens
/// at the pointer, flips up over the viewport and the inspector, and is painted after all of them, unclipped.
@MainActor
struct PaletteOverlayTests {
    @Test func thePaletteIsPaintedOverEverythingWhereItWasPlaced() async throws {
        let app = AppModel(kernel: FakeKernel(), file: GraphFile(graph: Graph(), viewState: ViewState(dock: .bottom)))
        await app.settle()
        app.viewport.recordViewSize(ViewportSize(width: 1400, height: 900))
        app.editor.pointerLocation = Vector2(200, 40)
        app.editor.openPalette()
        let palette = try #require(app.editor.palette)
        let panel = try #require(app.panelPlacement?.panel)
        #expect(palette.windowOrigin.y + PaletteLayout.size.y <= panel.origin.y + 10 + 46 + 40,
                "flipped up: its bottom edge is at the pointer")
        #expect(palette.windowOrigin.y < panel.origin.y, "so it reaches above the graph panel, over the viewport")

        let input = AppInput(model: app)
        let scene = renderFrame({ ZStack { AppRoot(model: app, input: input) } },
                                size: Size(width: Pixels(1400), height: Pixels(900)), scaleFactor: 2,
                                textSystem: CoreTextTextSystem(), atlas: GlyphAtlas(width: 1024, height: 1024))
        let index = try #require(scene.rects.firstIndex { rect in
            let drawn = frame(of: rect)
            return (drawn.origin - palette.windowOrigin).length < 0.5 && (drawn.size - PaletteLayout.size).length < 0.5
        }, "the palette's glass is drawn at its window origin")
        let mask = scene.rects[index].contentMask
        #expect(mask.size.width >= scene.rects[index].bounds.size.width
                && mask.size.height >= scene.rects[index].bounds.size.height, "not clipped by the graph panel")
        let position = try #require(paintPosition(of: .rect, at: index, in: scene))
        let surface = try #require(paintPosition(of: .surface, at: 0, in: scene))
        #expect(position > surface, "over the viewport")
        let panelGlass = try #require(scene.rects.firstIndex { (frame(of: $0).origin - panel.origin).length < 0.5 })
        #expect(try #require(paintPosition(of: .rect, at: panelGlass, in: scene)) < position, "over the graph panel")
        // Everything else in the window (the panels, the inspector, the top bar) is painted before it.
        let palettes = CanvasRect(origin: palette.windowOrigin - Vector2(0.5, 0.5), size: PaletteLayout.size + Vector2(1, 1))
        func inside(_ drawn: CanvasRect) -> Bool { palettes.contains(drawn.origin) && palettes.contains(drawn.origin + drawn.size) }
        let others = scene.rects.indices.filter { !inside(frame(of: scene.rects[$0])) }
            .compactMap { paintPosition(of: .rect, at: $0, in: scene) }
            + scene.glyphs.indices.filter { !inside(frame(of: scene.glyphs[$0].bounds)) }
            .compactMap { paintPosition(of: .glyph, at: $0, in: scene) }
        #expect(!others.isEmpty)
        #expect(others.allSatisfy { $0 < position }, "something outside the palette is painted over it")
    }

    /// A node-library type dragged out over the viewport is drawn at the pointer, over the viewport and the panel.
    @Test func aDraggedLibraryTypeIsPaintedOverTheWindow() async throws {
        let app = AppModel(kernel: FakeKernel(), file: GraphFile(graph: Graph(), viewState: ViewState(dock: .bottom)))
        await app.settle()
        app.viewport.recordViewSize(ViewportSize(width: 1400, height: 900))
        let panel = try #require(app.panelPlacement?.panel)
        let row = panel.origin + Vector2(60, 100), pointer = Vector2(700, 300)
        app.editor.moveLibraryDrag(FilletNode.typeID, from: row, to: pointer)
        #expect(app.editor.libraryDrag != nil)
        let input = AppInput(model: app)
        let scene = renderFrame({ ZStack { AppRoot(model: app, input: input) } },
                                size: Size(width: Pixels(1400), height: Pixels(900)), scaleFactor: 2,
                                textSystem: CoreTextTextSystem(), atlas: GlyphAtlas(width: 1024, height: 1024))
        let index = try #require(scene.rects.firstIndex { (frame(of: $0).origin - pointer).length < 0.5 },
                                 "the ghost is drawn at the pointer")
        let position = try #require(paintPosition(of: .rect, at: index, in: scene))
        #expect(position > (try #require(paintPosition(of: .surface, at: 0, in: scene))), "over the viewport")
        let panelGlass = try #require(scene.rects.firstIndex { (frame(of: $0).origin - panel.origin).length < 0.5 })
        #expect(try #require(paintPosition(of: .rect, at: panelGlass, in: scene)) < position, "over the graph panel")
    }
}
