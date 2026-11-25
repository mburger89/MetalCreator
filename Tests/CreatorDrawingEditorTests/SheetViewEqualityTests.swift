import CreatorGeometry
import CreatorStyle
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// `==` of the canvas layers covers every stored property (plan R27): an `.equatable()` view skips its content while `==` holds, so a
/// property missing from it would leave the screen stale. `expectEqualityCovers` fails when a layer gains a property with no variant.
@MainActor
@Suite("Sheet layer equality")
struct SheetViewEqualityTests {
    private let colors = DrawingColors(nil)
    private let stroke = SheetStroke(segments: [.line(Vector2(0, 0), Vector2(10, 0))], width: 0.5, layer: .visible)
    private let text = SheetText(run: DrawingText.layout("A", height: 2.5), original: "A", origin: Vector2(1, 1), height: 2.5)

    private func viewLayer(
        id: ViewID? = nil, strokes: [SheetStroke]? = nil, texts: [SheetText]? = nil, frame: Rect2D? = nil, zoom: Double = 2,
        paperHeight: Double = 210, isPending: Bool = false, isSelected: Bool = false, hovered: SheetStroke? = nil,
        problem: String? = nil, colors: DrawingColors? = nil, style: DrawingStyle = .iso
    ) -> SheetViewLayer {
        SheetViewLayer(
            id: id ?? fixedID, strokes: strokes ?? [stroke], texts: texts ?? [text],
            frame: frame ?? Rect2D(min: .zero, max: Vector2(10, 5)), zoom: zoom, paperHeight: paperHeight, isPending: isPending,
            isSelected: isSelected, hovered: hovered, problem: problem, colors: colors ?? self.colors, style: style)
    }

    private let fixedID = ViewID()

    @Test func theViewLayerReadsEveryPropertyInEquals() {
        var other = colors
        other.ink = HexColor(0x123456)
        var thicker = stroke
        thicker.width = 0.6
        expectEqualityCovers(
            viewLayer(), equalTo: viewLayer(),
            [
                "id": viewLayer(id: ViewID()),
                "strokes": viewLayer(strokes: [thicker]),
                "texts": viewLayer(texts: []),
                "frame": viewLayer(frame: Rect2D(min: .zero, max: Vector2(11, 5))),
                "zoom": viewLayer(zoom: 3),
                "paperHeight": viewLayer(paperHeight: 297),
                "isPending": viewLayer(isPending: true),
                "isSelected": viewLayer(isSelected: true),
                "hovered": viewLayer(hovered: stroke),
                "problem": viewLayer(problem: "The Output was removed."),
                "colors": viewLayer(colors: other),
                "style": viewLayer(style: .asme),
            ])
    }

    @Test func theFrameLayerReadsEveryPropertyInEquals() {
        func frameLayer(
            strokes: [SheetStroke]? = nil, texts: [SheetText]? = nil, zoom: Double = 2, paperHeight: Double = 210,
            colors: DrawingColors? = nil, style: DrawingStyle = .iso
        ) -> SheetFrameLayer {
            SheetFrameLayer(
                strokes: strokes ?? [stroke], texts: texts ?? [text], zoom: zoom, paperHeight: paperHeight,
                colors: colors ?? self.colors, style: style)
        }
        var other = colors
        other.paper = HexColor(0xeeeeee)
        expectEqualityCovers(
            frameLayer(), equalTo: frameLayer(),
            [
                "strokes": frameLayer(strokes: []),
                "texts": frameLayer(texts: []),
                "zoom": frameLayer(zoom: 3),
                "paperHeight": frameLayer(paperHeight: 297),
                "colors": frameLayer(colors: other),
                "style": frameLayer(style: .asme),
            ])
    }
}
