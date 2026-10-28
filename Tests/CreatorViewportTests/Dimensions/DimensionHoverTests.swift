import CreatorGeometry
import MetalUI
import Testing
@testable import CreatorViewport

/// A reference's source on hover (DIM-3 Task 15, spec §3.1): the editor's note for the text under the pointer, in a chip below it.
@MainActor
struct DimensionHoverTests {
    let id = OverlayDimensionID("a")
    let note = "from Number “width”"

    func makeModel() -> (model: ViewportModel, editor: FakeDimensionEditor) {
        let model = ViewportModel(kernel: StubMeshKernel(), pose: topDownPose(pointsPerMillimetre: 2), clock: ManualClock())
        model.viewSize = dimensionTestSize
        let editor = FakeDimensionEditor()
        editor.notes[id] = note
        model.dimensionEditor = editor
        model.showDimensions([sixtyMillimetres()])
        return (model, editor)
    }

    func centre(of placed: PlacedDimension) -> ScreenPoint {
        ScreenPoint(placed.textOrigin.x + placed.textSize.width / 2, placed.textOrigin.y + placed.textSize.height / 2)
    }

    @Test func hoveringATextAsksItsEditorForANote() throws {
        let (model, editor) = makeModel()  // the model holds its editor weakly
        defer { withExtendedLifetime(editor) {} }
        let placed = try #require(model.placedDimensions(measuring: .eightPerCharacter).first)
        #expect(model.dimensionHoverNote == nil)
        model.pointerHovered(at: centre(of: placed))
        #expect(model.hoveredDimension == id)
        let shown = try #require(model.dimensionHoverNote)
        #expect(shown.id == id && shown.text == note)
        #expect(shown.at == ScreenPoint(placed.textOrigin.x + placed.textSize.width / 2,
                                        placed.textOrigin.y + placed.textSize.height + DimensionStyle.ansi.textGap))
    }

    @Test func noNoteOffTheTextOrWhileAnimating() throws {
        let (model, editor) = makeModel()
        let placed = try #require(model.placedDimensions(measuring: .eightPerCharacter).first)
        model.pointerHovered(at: ScreenPoint(1, 1))
        #expect(model.hoveredDimension == nil && model.dimensionHoverNote == nil)
        model.pointerHovered(at: centre(of: placed))
        #expect(model.dimensionHoverNote != nil)
        model.pointerHovered(at: nil)
        #expect(model.hoveredDimension == nil && model.dimensionHoverNote == nil, "the pointer left the view")

        model.pointerHovered(at: centre(of: placed))
        model.perform(.view(.front))
        #expect(model.isAnimating)
        model.pointerHovered(at: centre(of: placed))
        #expect(model.hoveredDimension == nil && model.dimensionHoverNote == nil)

        let plain = makeModel().model
        editor.notes = [:]
        plain.dimensionEditor = editor
        let drawn = try #require(plain.placedDimensions(measuring: .eightPerCharacter).first)
        plain.pointerHovered(at: centre(of: drawn))
        #expect(plain.hoveredDimension == id)
        #expect(plain.dimensionHoverNote == nil, "an editor with nothing to say")
    }

    @Test func theChipDrawsItsText() throws {
        let scale = 2.0
        let origin = ScreenPoint(20, 30)
        let scene = renderFrame({
            ZStack(alignment: .topLeading) {
                DimensionHoverChip(note: "from Number", origin: origin, size: ViewportSize(width: 120, height: 26),
                                   ink: .white, fill: .black)
            }
        }, size: Size(width: Pixels(400), height: Pixels(300)), scaleFactor: Float(scale),
                                textSystem: testTextSystem(), atlas: GlyphAtlas(width: 512, height: 512))
        #expect(scene.glyphs.count == 10, "“from Number” without its space")
        for glyph in scene.glyphs {
            let x = Double(glyph.bounds.origin.x) / scale, y = Double(glyph.bounds.origin.y) / scale
            #expect(x >= origin.x && x <= origin.x + 120 && y >= origin.y && y <= origin.y + 26, "inside the chip, at its origin")
        }
        #expect(!scene.rects.isEmpty, "the rounded fill")
    }
}
