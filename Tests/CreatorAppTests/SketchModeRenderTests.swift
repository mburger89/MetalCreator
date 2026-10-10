import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorSketchEditor
import MetalUI
import MetalUIText
import Testing
@testable import CreatorApp
@testable import CreatorViewport

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

    /// The view cube's arrows, Home button and View menu are hidden while sketching (the camera is locked to the
    /// plane), and come back when the sketch ends.
    @Test func theViewCubesControlsAreHiddenWhileSketching() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox(rectangleSketch())
        let app = AppModel(kernel: FakeKernel(), file: GraphFile(graph: builder.graph))
        await app.settle()
        app.beginSketch(for: box.sketch.id)
        await app.settle()
        #expect(cubeControlGlyphs(app) == 0)
        app.finishSketch()
        #expect(cubeControlGlyphs(app) > 0)
    }

    /// The pointer readout's chip is drawn just above the pointer while drawing, and goes when the sketch ends.
    @Test func theReadoutIsDrawnAboveThePointer() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox(rectangleSketch())
        let app = AppModel(kernel: FakeKernel(), file: GraphFile(graph: builder.graph))
        await app.settle()
        app.viewport.recordViewSize(ViewportSize(width: 1400, height: 900))
        app.beginSketch(for: box.sketch.id)
        await app.settle()
        await app.viewport.waitForAnimation()
        let editor = try #require(app.sketch?.editor)
        editor.choose(.point)
        let pointer = ScreenPoint(700, 500)
        app.viewport.pointerHovered(at: pointer)
        let chip = try #require(editor.readoutChip)
        #expect(chip.origin.y + chip.size.height < pointer.y, "above the pointer")
        #expect(glyphs(in: chip, of: app) > 0)
        app.finishSketch()
        #expect(glyphs(in: chip, of: app) == 0, "gone outside sketch mode")
    }

    /// Dragging a sketch point draws the chip by the pointer at each drag step (the viewport sends the tool the drag,
    /// no hover), and the release takes it away.
    @Test func theReadoutFollowsAPointDrag() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox(rectangleSketch())
        let app = AppModel(kernel: FakeKernel(), file: GraphFile(graph: builder.graph))
        await app.settle()
        app.viewport.recordViewSize(ViewportSize(width: 1400, height: 900))
        app.beginSketch(for: box.sketch.id)
        await app.settle()
        await app.viewport.waitForAnimation()
        let editor = try #require(app.sketch?.editor)
        editor.choose(.select)
        let corner = try #require(app.viewport.projector.screenPoint(of: Vector3(60, 40, 0)))
        let step = ScreenPoint(corner.x + 30, corner.y + 30)
        app.viewport.dragChanged(from: corner, to: step, modifiers: [], button: .primary)
        let chip = try #require(editor.readoutChip)
        #expect(chip.text == "60.0, 40.0", "the fully constrained corner stays where the solve keeps it")
        #expect(chip == ReadoutChip(text: chip.text, pointer: step, in: ViewportSize(width: 1400, height: 900),
                                    modelArea: app.viewport.projector.modelArea), "by the pointer, not the press")
        #expect(glyphs(in: chip, of: app) > 0)
        app.viewport.dragEnded(from: corner, at: step, modifiers: [], button: .primary)
        #expect(editor.readoutChip == nil)
        #expect(glyphs(in: chip, of: app) == 0, "gone with the release")
    }

    /// The chip is painted over the window's chrome (the top bar, the panels), never under their glass.
    @Test func theReadoutIsPaintedOverTheChrome() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox(rectangleSketch())
        let app = AppModel(kernel: FakeKernel(), file: GraphFile(graph: builder.graph))
        await app.settle()
        app.viewport.recordViewSize(ViewportSize(width: 1400, height: 900))
        app.beginSketch(for: box.sketch.id)
        await app.settle()
        await app.viewport.waitForAnimation()
        let editor = try #require(app.sketch?.editor)
        editor.choose(.point)
        app.viewport.pointerHovered(at: ScreenPoint(700, 500))
        let chip = try #require(editor.readoutChip)
        let input = AppInput(model: app)
        let scene = renderFrame({ ZStack { AppRoot(model: app, input: input) } }, size: Size(width: Pixels(1400), height: Pixels(900)),
                                scaleFactor: 2, textSystem: CoreTextTextSystem(), atlas: GlyphAtlas(width: 1024, height: 1024))
        func inChip(_ bounds: MUIBounds) -> Bool {
            let drawn = frame(of: bounds)
            return drawn.origin.x >= chip.origin.x - 0.5 && drawn.origin.y >= chip.origin.y - 0.5
                && drawn.origin.x + drawn.size.x <= chip.origin.x + chip.size.width + 0.5
                && drawn.origin.y + drawn.size.y <= chip.origin.y + chip.size.height + 0.5
        }
        let chipGlyphs = scene.glyphs.indices.filter { inChip(scene.glyphs[$0].bounds) }
            .compactMap { paintPosition(of: .glyph, at: $0, in: scene) }
        let others = scene.rects.indices.filter { !inChip(scene.rects[$0].bounds) }
            .compactMap { paintPosition(of: .rect, at: $0, in: scene) }
        #expect(!chipGlyphs.isEmpty && !others.isEmpty)
        #expect((others.max() ?? 0) < (chipGlyphs.min() ?? 0), "a panel's glass is painted over the chip")
    }

    /// Glyphs of the whole window drawn inside `chip`'s frame.
    func glyphs(in chip: ReadoutChip, of app: AppModel) -> Int {
        let input = AppInput(model: app)
        let scene = renderFrame({ ZStack { AppRoot(model: app, input: input) } }, size: Size(width: Pixels(1400), height: Pixels(900)),
                                scaleFactor: 2, textSystem: CoreTextTextSystem(), atlas: GlyphAtlas(width: 1024, height: 1024))
        return scene.glyphs.filter { glyph in
            let x = Double(glyph.bounds.origin.x + glyph.bounds.size.width / 2) / 2
            let y = Double(glyph.bounds.origin.y + glyph.bounds.size.height / 2) / 2
            return x >= chip.origin.x && x <= chip.origin.x + chip.size.width
                && y >= chip.origin.y && y <= chip.origin.y + chip.size.height
        }.count
    }

    /// Glyphs drawn where the viewport puts the cube's controls: just below the cube, at its left.
    func cubeControlGlyphs(_ app: AppModel) -> Int {
        let viewport = app.viewport
        let scene = renderFrame({ ZStack { ViewportView(model: viewport) } }, size: Size(width: Pixels(1400), height: Pixels(900)),
                                scaleFactor: 2, textSystem: CoreTextTextSystem(), atlas: GlyphAtlas(width: 1024, height: 1024))
        let cube = viewport.cubeLayout
        let top = cube.origin.y + cube.side
        return scene.glyphs.filter { glyph in
            let x = Double(glyph.bounds.origin.x + glyph.bounds.size.width / 2) / 2
            let y = Double(glyph.bounds.origin.y + glyph.bounds.size.height / 2) / 2
            return x >= cube.origin.x && x <= cube.origin.x + 240 && y >= top && y <= top + 80
        }.count
    }

    func glyphCount<View: ElementGroup>(_ view: () -> View) -> Int {
        let content = view()
        return renderFrame({ ZStack { content } }, size: Size(width: Pixels(1400), height: Pixels(900)), scaleFactor: 2,
                           textSystem: CoreTextTextSystem(), atlas: GlyphAtlas(width: 1024, height: 1024)).glyphs.count
    }
}
