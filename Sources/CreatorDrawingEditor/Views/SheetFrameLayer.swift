import CreatorDrawing
import CreatorStyle
import MetalUI

/// The sheet's border, zones and title block, and the annotations that belong to no view: everything of the picture that
/// belongs to no view, with the sheet's pictures under the ink (DR-5 R12). `.equatable()`, `==` over every stored property.
struct SheetFrameLayer: Component, Equatable {
    let strokes: [SheetStroke]
    let texts: [SheetText]
    let fills: [SheetFill]
    let images: [SheetImage]
    let bitmaps: SheetBitmaps
    let zoom: Double
    let paperHeight: Double
    let colors: DrawingColors
    let style: DrawingStyle

    var content: some ElementGroup {
        ZStack(alignment: .topLeading) {
            SheetImageLayer(images: images, bitmaps: bitmaps, zoom: zoom, paperHeight: paperHeight)
            SheetStrokeGroups(
                strokes: strokes, zoom: zoom, paperHeight: paperHeight, ink: colors.ink, style: style, fills: fills,
                warning: colors.warning)
            SheetTexts(
                texts: texts, zoom: zoom, paperHeight: paperHeight, ink: colors.ink, warning: colors.warning)
        }
    }
}
