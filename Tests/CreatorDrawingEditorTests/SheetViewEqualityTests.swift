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

    private func bucket(_ revision: Int = 1) -> SheetLayers.Bucket {
        SheetLayers.Bucket(strokes: [stroke], fills: [fill], texts: [text], revision: revision)
    }

    private func viewLayer(
        id: ViewID? = nil, bucket: SheetLayers.Bucket? = nil, zoom: Double = 2, paperHeight: Double = 210, isPending: Bool = false,
        colors: DrawingColors? = nil, style: DrawingStyle = .iso
    ) -> SheetViewLayer {
        SheetViewLayer(
            id: id ?? fixedID, bucket: bucket ?? self.bucket(), zoom: zoom, paperHeight: paperHeight, isPending: isPending,
            colors: colors ?? self.colors, style: style)
    }

    private func annotationLayer(
        id: ViewID? = nil, bucket: SheetLayers.Bucket? = nil, frame: Rect2D? = nil, zoom: Double = 2, paperHeight: Double = 210,
        isPending: Bool = false, isSelected: Bool = false, hovered: SheetStroke? = nil, colors: DrawingColors? = nil,
        style: DrawingStyle = .iso
    ) -> SheetAnnotationLayer {
        SheetAnnotationLayer(
            id: id ?? fixedID, bucket: bucket ?? self.bucket(), frame: frame ?? Rect2D(min: .zero, max: Vector2(10, 5)), zoom: zoom,
            paperHeight: paperHeight, isPending: isPending, isSelected: isSelected, hovered: hovered,
            colors: colors ?? self.colors, style: style)
    }

    private let fixedID = ViewID()
    private let sharedBitmaps = SheetBitmaps()
    private var image: SheetImage {
        SheetImage(
            rect: Rect2D(min: .zero, max: Vector2(4, 3)),
            pixels: GreyPixels(key: "k", width: 2, height: 1, bytes: [0, 255])!)
    }
    private let fill = SheetFill(points: [Vector2(0, 0), Vector2(2, 0), Vector2(1, 1)])

    @Test func theViewLayerReadsEveryPropertyInEquals() {
        var other = colors
        other.ink = HexColor(0x123456)
        expectEqualityCovers(
            viewLayer(), equalTo: viewLayer(),
            [
                "id": viewLayer(id: ViewID()),
                "bucket": viewLayer(bucket: bucket(2)),
                "zoom": viewLayer(zoom: 3),
                "paperHeight": viewLayer(paperHeight: 297),
                "isPending": viewLayer(isPending: true),
                "colors": viewLayer(colors: other),
                "style": viewLayer(style: .asme),
            ])
    }

    @Test func theAnnotationLayerReadsEveryPropertyInEquals() {
        var other = colors
        other.ink = HexColor(0x123456)
        expectEqualityCovers(
            annotationLayer(), equalTo: annotationLayer(),
            [
                "id": annotationLayer(id: ViewID()),
                "bucket": annotationLayer(bucket: bucket(2)),
                "frame": annotationLayer(frame: Rect2D(min: .zero, max: Vector2(11, 5))),
                "zoom": annotationLayer(zoom: 3),
                "paperHeight": annotationLayer(paperHeight: 297),
                "isPending": annotationLayer(isPending: true),
                "isSelected": annotationLayer(isSelected: true),
                "hovered": annotationLayer(hovered: stroke),
                "colors": annotationLayer(colors: other),
                "style": annotationLayer(style: .asme),
            ])
    }

    @Test func aLayerComparesRevisionsNotArrays() {
        var other = bucket(1)
        other.strokes = []
        #expect(viewLayer(bucket: other) == viewLayer(bucket: bucket(1)), "the revision stands for the contents")
        #expect(annotationLayer(bucket: other) == annotationLayer(bucket: bucket(1)))
    }

    @Test func theFrameLayerReadsEveryPropertyInEquals() {
        func frameLayer(
            bucket: SheetLayers.Bucket? = nil, images: [SheetImage]? = nil,
            bitmaps: SheetBitmaps? = nil, zoom: Double = 2, paperHeight: Double = 210, colors: DrawingColors? = nil,
            style: DrawingStyle = .iso
        ) -> SheetFrameLayer {
            SheetFrameLayer(
                bucket: bucket ?? self.bucket(), images: images ?? [image],
                bitmaps: bitmaps ?? sharedBitmaps, zoom: zoom, paperHeight: paperHeight, colors: colors ?? self.colors, style: style)
        }
        var other = colors
        other.paper = HexColor(0xeeeeee)
        expectEqualityCovers(
            frameLayer(), equalTo: frameLayer(),
            [
                "bucket": frameLayer(bucket: bucket(2)),
                "images": frameLayer(images: []),
                "bitmaps": frameLayer(bitmaps: SheetBitmaps()),
                "zoom": frameLayer(zoom: 3),
                "paperHeight": frameLayer(paperHeight: 297),
                "colors": frameLayer(colors: other),
                "style": frameLayer(style: .asme),
            ])
    }

    @Test func theSelectionLayerReadsEveryPropertyInEquals() {
        func layer(
            strokes: [SheetStroke]? = nil, fills: [SheetFill]? = nil, texts: [SheetText]? = nil, ring: Vector2? = nil,
            zoom: Double = 2, paperHeight: Double = 210, colors: DrawingColors? = nil, style: DrawingStyle = .iso
        ) -> SheetSelectionLayer {
            SheetSelectionLayer(
                strokes: strokes ?? [stroke], fills: fills ?? [fill], texts: texts ?? [text], ring: ring, zoom: zoom,
                paperHeight: paperHeight, colors: colors ?? self.colors, style: style)
        }
        var other = colors
        other.highlight = HexColor(0x123456)
        expectEqualityCovers(
            layer(), equalTo: layer(),
            [
                "strokes": layer(strokes: []),
                "fills": layer(fills: []),
                "texts": layer(texts: []),
                "ring": layer(ring: Vector2(1, 1)),
                "zoom": layer(zoom: 3),
                "paperHeight": layer(paperHeight: 297),
                "colors": layer(colors: other),
                "style": layer(style: .asme),
            ])
    }

    @Test func theImageLayerReadsEveryPropertyInEquals() {
        func layer(
            images: [SheetImage]? = nil, bitmaps: SheetBitmaps? = nil, zoom: Double = 2, paperHeight: Double = 210
        ) -> SheetImageLayer {
            SheetImageLayer(images: images ?? [image], bitmaps: bitmaps ?? sharedBitmaps, zoom: zoom, paperHeight: paperHeight)
        }
        expectEqualityCovers(
            layer(), equalTo: layer(),
            [
                "images": layer(images: []),
                "bitmaps": layer(bitmaps: SheetBitmaps()),
                "zoom": layer(zoom: 3),
                "paperHeight": layer(paperHeight: 297),
            ])
    }

    @Test func aBitmapIsMadeOncePerKey() {
        let bitmaps = SheetBitmaps()
        let one = bitmaps.bitmap(for: image.pixels)
        #expect(one.width == 2 && one.height == 1)
        #expect(bitmaps.count == 1)
        _ = bitmaps.bitmap(for: image.pixels)
        #expect(bitmaps.count == 1)
    }
}
