import CreatorDrawing
import CreatorStyle
import MetalUI

/// The sheet's border, zones and title block: everything of the picture that belongs to no view. `.equatable()`, `==` over every
/// stored property.
struct SheetFrameLayer: Component, Equatable {
    let strokes: [SheetStroke]
    let texts: [SheetText]
    let zoom: Double
    let paperHeight: Double
    let colors: DrawingColors
    let style: DrawingStyle

    var content: some ElementGroup {
        ZStack(alignment: .topLeading) {
            SheetStrokeGroups(strokes: strokes, zoom: zoom, paperHeight: paperHeight, ink: colors.ink, style: style)
            SheetTexts(
                texts: texts, zoom: zoom, paperHeight: paperHeight, ink: colors.ink, warning: colors.warning, problem: nil)
        }
    }
}
