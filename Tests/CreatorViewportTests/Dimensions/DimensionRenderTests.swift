import CreatorGeometry
import MetalUI
import Testing
@testable import CreatorViewport

/// A dimension drawn over the scene: its text inside its box, its lines and arrows painted, no text when the layout
/// hides it. `DimensionView` is rendered alone, so these run on every platform.
@MainActor
struct DimensionRenderTests {
    let size = Size(width: Pixels(400), height: Pixels(300))
    let scale = 2.0

    func placed(measure: TextMeasure) throws -> PlacedDimension {
        let camera = topDownCamera(pointsPerMillimetre: 4)
        return try #require(DimensionLayout.place(sixtyMillimetres(), style: .ansi, camera: camera, measure: measure))
    }

    func scene(_ dimension: PlacedDimension) -> Scene {
        renderFrame({ ZStack(alignment: .topLeading) { DimensionView(placed: dimension, style: .ansi, ink: .white, fill: .black) } },
                    size: size, scaleFactor: Float(scale), textSystem: testTextSystem(),
                    atlas: GlyphAtlas(width: 512, height: 512))
    }

    @Test func theTextIsDrawnInsideItsBox() throws {
        let dimension = try placed(measure: .real())
        let inside = scene(dimension).glyphs.filter { glyph in
            let x = Double(glyph.bounds.origin.x + glyph.bounds.size.width / 2) / scale
            let y = Double(glyph.bounds.origin.y + glyph.bounds.size.height / 2) / scale
            return x >= dimension.textOrigin.x && x <= dimension.textOrigin.x + dimension.textSize.width
                && y >= dimension.textOrigin.y && y <= dimension.textOrigin.y + dimension.textSize.height
        }
        #expect(inside.count == 2, "6 and 0")
    }

    @Test func linesAndArrowsArePainted() throws {
        let dimension = try placed(measure: .real())
        #expect(!dimension.segments.isEmpty && !dimension.arrows.isEmpty)
        #expect(!scene(dimension).images.isEmpty, "shapes are rasterized paths")
    }

    @Test func aHiddenTextDrawsNoGlyphs() throws {
        var dimension = try placed(measure: .real())
        dimension.showsText = false
        let hidden = scene(dimension)
        #expect(hidden.glyphs.isEmpty)
        #expect(!hidden.images.isEmpty, "the lines are still drawn")
    }

    #if canImport(Metal)
    @Test func theViewportDrawsEachDimensionsText() throws {
        let model = ViewportModel(kernel: StubMeshKernel(), pose: topDownPose(pointsPerMillimetre: 4), clock: ManualClock())
        model.viewSize = ViewportSize(width: 1400, height: 900)
        model.showDimensions([sixtyMillimetres()])
        let dimension = try #require(model.placedDimensions(measuring: .real()).first)
        let scene = renderFrame({ ZStack { ViewportView(model: model) } }, size: Size(width: Pixels(1400), height: Pixels(900)),
                                scaleFactor: 2, textSystem: testTextSystem(), atlas: GlyphAtlas(width: 1024, height: 1024))
        let inside = scene.glyphs.filter { glyph in
            let x = Double(glyph.bounds.origin.x + glyph.bounds.size.width / 2) / 2
            let y = Double(glyph.bounds.origin.y + glyph.bounds.size.height / 2) / 2
            return x >= dimension.textOrigin.x && x <= dimension.textOrigin.x + dimension.textSize.width
                && y >= dimension.textOrigin.y && y <= dimension.textOrigin.y + dimension.textSize.height
        }
        #expect(inside.count == 2)
    }
    #endif
}
