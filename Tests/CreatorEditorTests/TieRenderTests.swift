import CreatorGeometry
import CreatorGraph
import CreatorStyle
import MetalUI
import Testing
@testable import CreatorEditor

/// How wires and ties draw (cable ties spec 2026-10-26 §4.1, §5.1): a tied wire through its lane, a selected wire wider in the
/// selection colour, a band in the glass stroke above the wires and below notes and nodes (in the selection colour when
/// selected), selected ties last, and ties culled by their band.
@MainActor
struct TieRenderTests {
    let scene = TieScene()

    func canvasOrigin(_ editor: EditorModel) -> Vector2 {
        GraphPanelLayout.canvasFrame(inPanelOf: Vector2(900, 600), flow: editor.flow, showsLibrary: editor.showsLibrary).origin
    }

    /// The top-left of the rect painted last at `point` (display canvas points), in canvas points.
    func painted(at point: Vector2, in scene: Scene, _ editor: EditorModel) -> Vector2? {
        let origin = canvasOrigin(editor)
        return topRect(at: origin + point, in: scene).map { screenFrame(of: $0, in: scene).origin - origin }
    }

    func panel(_ editor: EditorModel) -> Scene {
        renderHeadless { GraphPanel(model: editor, input: GraphPanelInput(model: editor)) }
    }

    func isColour(_ rect: MUIRect?, _ colour: HexColor) -> Bool {
        guard let rect else { return false }
        let want = colour.hsla
        return abs(rect.background.h - want.h) < 0.01 && abs(rect.background.s - want.s) < 0.01
            && abs(rect.background.l - want.l) < 0.01 && abs(rect.background.a - want.a) < 0.01
    }

    @Test func aTiedWireIsDrawnThroughItsLane() throws {
        let editor = scene.editor(ties: [scene.tie()])
        let wire = try #require(CanvasLayers.wires(editor).first { $0.route.wire == scene.upper })
        #expect(wire.id == "\(scene.b1.id.rawValue.uuidString).value")
        #expect(wire.route.pinned == [Vector2(168, 60), Vector2(384, 158), Vector2(600, 60)])
        #expect(wire.color == Palette.dracula.socket(.number) && wire.lineWidth == WireView.defaultLineWidth)
    }

    @Test func aSelectedWireIsWiderInTheSelectionColour() {
        let editor = scene.editor()
        editor.canvasSelection = CanvasSelection(wires: [scene.upper])
        let wires = CanvasLayers.wires(editor)
        let upper = wires.first { $0.route.wire == scene.upper }, lower = wires.first { $0.route.wire == scene.lower }
        #expect(upper?.color == Palette.dracula.selection && upper?.lineWidth == CanvasLayers.selectedLineWidth)
        #expect(lower?.color == Palette.dracula.socket(.number) && lower?.lineWidth == WireView.defaultLineWidth)
        #expect(!editor.document.canUndo, "selection is view state")
    }

    @Test func bandsDrawAboveTheWiresAndBelowNotesAndNodes() {
        let band = Vector2(384, 160)
        let editor = scene.editor(ties: [scene.tie()])
        #expect(painted(at: band, in: panel(editor), editor) == Vector2(381, 155), "the band, where nothing is above it")
        let noted = scene.editor(ties: [scene.tie()], stickies: [note(1, at: Vector2(370, 150), size: Vector2(40, 40))])
        #expect(painted(at: band, in: panel(noted), noted) == Vector2(370, 150), "a note covers the band")
        let under = scene.editor(ties: [scene.tie(at: Vector2(84, 30))])
        #expect(painted(at: Vector2(84, 30), in: panel(under), under) == Vector2(0, 0), "a node covers the band")
    }

    @Test func aBandIsTheGlassStrokeAndASelectedOneTheSelectionColour() {
        let editor = scene.editor(ties: [scene.tie()])
        let point = canvasOrigin(editor) + Vector2(384, 160)
        #expect(isColour(topRect(at: point, in: panel(editor)), Palette.dracula.hairline))
        editor.canvasSelection = CanvasSelection(ties: [tieID(1)])
        #expect(isColour(topRect(at: point, in: panel(editor)), Palette.dracula.selection))
    }

    @Test func selectedTiesDrawLast() {
        let editor = scene.editor(ties: [scene.tie(1), scene.tie(2, at: Vector2(384, 161))])
        #expect(editor.drawOrderTies(in: editor.wireRouting).map(\.id) == [tieID(1), tieID(2)])
        editor.canvasSelection = CanvasSelection(ties: [tieID(1)])
        #expect(editor.drawOrderTies(in: editor.wireRouting).map(\.id) == [tieID(2), tieID(1)])
    }

    @Test func aTieWhollyOutsideTheCanvasIsNotBuilt() {
        let editor = scene.editor(ties: [scene.tie(), scene.tie(2, at: Vector2(9_000, 9_000))])
        #expect(editor.drawnTies(in: editor.wireRouting).map(\.id) == [tieID(1), tieID(2)], "unplaced, everything is drawn")
        editor.panelPlacement = PanelPlacement(window: Vector2(1000, 700),
                                               panel: CanvasRect(origin: Vector2(12, 388), size: Vector2(976, 300)))
        #expect(editor.drawnTies(in: editor.wireRouting).map(\.id) == [tieID(1)])
    }

    @Test func aBandIsEqualOnlyWhenEveryInputIs() {
        let band = CanvasRect(origin: Vector2(381, 155), size: Vector2(6, 10))
        expectEqualityCovers(TieBandView(band: band, isSelected: false, palette: .dracula),
                             equalTo: TieBandView(band: band, isSelected: false, palette: .dracula), [
            "band": TieBandView(band: band.moved(by: Vector2(1, 0)), isSelected: false, palette: .dracula),
            "isSelected": TieBandView(band: band, isSelected: true, palette: .dracula),
            "palette": TieBandView(band: band, isSelected: false, palette: Palette(.alucard)),
        ])
    }
}
