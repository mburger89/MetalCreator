import CreatorDrawing
import CreatorStyle
import MetalUI

/// The sheet's border, zones and title block, and the annotations that belong to no view: everything of the picture that
/// belongs to no view, with the sheet's pictures under the ink (DR-5 R12). `.equatable()`, `==` over every stored property, the
/// bucket by its `revision`.
struct SheetFrameLayer: Component, Equatable {
    let bucket: SheetLayers.Bucket
    let images: [SheetImage]
    let bitmaps: SheetBitmaps
    let zoom: Double
    let paperHeight: Double
    let colors: DrawingColors
    let style: DrawingStyle

    nonisolated static func == (lhs: SheetFrameLayer, rhs: SheetFrameLayer) -> Bool {
        lhs.bucket.revision == rhs.bucket.revision && lhs.images == rhs.images && lhs.bitmaps == rhs.bitmaps
            && lhs.zoom == rhs.zoom && lhs.paperHeight == rhs.paperHeight && lhs.colors == rhs.colors && lhs.style == rhs.style
    }

    var content: some ElementGroup {
        ZStack(alignment: .topLeading) {
            SheetImageLayer(images: images, bitmaps: bitmaps, zoom: zoom, paperHeight: paperHeight)
            SheetStrokeGroups(
                strokes: bucket.strokes, zoom: zoom, paperHeight: paperHeight, ink: colors.ink, style: style, fills: bucket.fills,
                warning: colors.warning)
            SheetTexts(
                texts: bucket.texts, zoom: zoom, paperHeight: paperHeight, ink: colors.ink, warning: colors.warning)
        }
    }
}
