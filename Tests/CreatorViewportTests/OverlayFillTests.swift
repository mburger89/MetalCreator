import CreatorGeometry
import CreatorStyle
import Testing
@testable import CreatorViewport

/// Filled overlay triangles (sketcher spec §8's faint green region fill): the `.region` tint, three vertices a
/// triangle in the tint's colour, and fills counting as overlay content. The GPU side is pinned by `GPUDataTests`
/// (the vertex stride) and `OffscreenRenderTests` (a fill tints the pixels it covers).
struct OverlayFillTests {
    let triangle = [Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(0, 10, 0)]

    @Test func theRegionTintIsTheSketchNodesGreenFaded() {
        let theme = ColorTheme.dracula
        let colour = ViewportPalette(theme).color(.region)
        let header = theme.colors.profileHeader.rgba
        #expect(colour.x == header.x && colour.y == header.y && colour.z == header.z)
        #expect(colour.w > 0 && colour.w < 0.5, "faint: the model and the grid show through")
    }

    @Test func eachTriangleBecomesThreeVerticesInTheTintsColour() {
        let shifted = triangle.map { $0 + Vector3(20, 0, 0) }
        let fills = [OverlayFill(vertices: triangle + shifted), OverlayFill(vertices: triangle, tint: .selected)]
        let vertices = OverlayGeometry.fillVertices(fills, palette: .dracula)
        #expect(vertices.count == 9)
        #expect(vertices[0].color == ViewportPalette.dracula.sketchRegion)
        #expect(vertices[3].position == SIMD3<Float>(20, 0, 0))
        #expect(vertices[6].color == ViewportPalette.dracula.sketchSelected)
    }

    @Test func aTrailingVertexOrTwoAreIgnored() {
        let fill = OverlayFill(vertices: triangle + [Vector3(1, 1, 1), Vector3(2, 2, 2)])
        #expect(fill.triangleCount == 1)
        #expect(OverlayGeometry.fillVertices([fill], palette: .dracula).count == 3)
        #expect(OverlayGeometry.fillVertices([OverlayFill(vertices: [])], palette: .dracula).isEmpty)
    }

    @Test func fillsAreOverlayContent() {
        #expect(ViewportOverlay().isEmpty)
        #expect(!ViewportOverlay(fills: [OverlayFill(vertices: triangle)]).isEmpty)
    }
}
