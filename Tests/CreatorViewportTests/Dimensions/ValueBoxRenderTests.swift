import CreatorGeometry
import MetalUI
import Testing
@testable import CreatorViewport

/// The value box drawn over the scene (spec §7): the draft inside its box, a refusal or "Checking…" under it.
/// `DimensionValueBoxView` is rendered alone, so these run on every platform.
@MainActor
struct ValueBoxRenderTests {
    let id = OverlayDimensionID("a")
    let size = Size(width: Pixels(400), height: Pixels(300))
    let scale = 2.0

    /// A model with the 60 mm dimension shown and its box open on `text`.
    func openModel(text: String = "70") throws -> ViewportModel {
        let model = ViewportModel(kernel: StubMeshKernel(), pose: topDownPose(pointsPerMillimetre: 4), clock: ManualClock())
        model.viewSize = ViewportSize(width: 400, height: 300)
        let editor = FakeDimensionEditor()
        editor.contents[id] = DimensionValueBoxContent(text: text, note: nil)
        model.dimensionEditor = editor
        model.showDimensions([sixtyMillimetres()])
        _ = try model.placedDimensions(measuring: .real())
        #expect(model.openValueBox(for: id))
        return model
    }

    func scene(_ model: ViewportModel, _ placed: PlacedValueBox) -> Scene {
        renderFrame({ ZStack(alignment: .topLeading) { DimensionValueBoxView(model: model, placed: placed) }
                       .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading) },
                    size: size, scaleFactor: Float(scale), textSystem: testTextSystem(),
                    atlas: GlyphAtlas(width: 512, height: 512))
    }

    /// The vertical centre of a glyph, in points.
    func centreY(_ glyph: MUIGlyph) -> Double {
        Double(glyph.bounds.origin.y + glyph.bounds.size.height / 2) / scale
    }

    func centreX(_ glyph: MUIGlyph) -> Double {
        Double(glyph.bounds.origin.x + glyph.bounds.size.width / 2) / scale
    }

    @Test func theDraftIsDrawnInTheBox() throws {
        let model = try openModel()
        let placed = try #require(model.placedValueBox(measuring: .real()))
        let inside = scene(model, placed).glyphs.filter { glyph in
            centreX(glyph) >= placed.origin.x && centreX(glyph) <= placed.origin.x + placed.size.width
                && centreY(glyph) >= placed.origin.y && centreY(glyph) <= placed.origin.y + placed.size.height
        }
        #expect(inside.count == 2, "7 and 0")
    }

    @Test func aRefusalIsDrawnUnderTheBox() throws {
        let model = try openModel()
        model.valueBox?.message = "Not a length"
        let placed = try #require(model.placedValueBox(measuring: .real()))
        let bottom = placed.origin.y + placed.size.height
        let below = scene(model, placed).glyphs.filter { centreY($0) > bottom }
        #expect(below.count == "Not a length".filter { !$0.isWhitespace }.count)
    }

    @Test func checkingSaysSo() throws {
        let model = try openModel()
        model.valueBox?.isChecking = true
        let placed = try #require(model.placedValueBox(measuring: .real()))
        let bottom = placed.origin.y + placed.size.height
        let below = scene(model, placed).glyphs.filter { centreY($0) > bottom }
        #expect(below.count == "Checking…".count)
    }
}
