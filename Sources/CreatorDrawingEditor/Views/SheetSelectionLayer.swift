import CreatorDrawing
import CreatorGeometry
import CreatorStyle
import MetalUI

/// What is highlighted over the sheet: the selected annotations, the annotation being drafted, the line the annotation tool would pick
/// and, for a corner or a centre, a ring (plan R17: 1.5 mm). All in the highlight colour. `.equatable()`, `==` over every stored
/// property, so a pan or an unrelated change skips it.
struct SheetSelectionLayer: Component, Equatable {
    let strokes: [SheetStroke]
    let fills: [SheetFill]
    let texts: [SheetText]
    /// Where the hover ring stands, in sheet millimetres.
    let ring: Vector2?
    let zoom: Double
    let paperHeight: Double
    let colors: DrawingColors
    let style: DrawingStyle

    /// The ring's radius in sheet millimetres.
    static let ringRadius = 1.5

    var content: some ElementGroup {
        ZStack(alignment: .topLeading) {
            SheetStrokeGroups(
                strokes: strokes, zoom: zoom, paperHeight: paperHeight, ink: colors.highlight, style: style, fills: fills,
                warning: colors.highlight)
            SheetTexts(
                texts: texts, zoom: zoom, paperHeight: paperHeight, ink: colors.highlight, warning: colors.highlight)
            if let ring {
                let circle = SheetStroke(
                    segments: [.arc(center: ring, radius: Self.ringRadius, start: 0, sweep: 2 * .pi)], width: 0.25, layer: .dimension)
                SheetStrokeGroups(
                    strokes: [circle], zoom: zoom, paperHeight: paperHeight, ink: colors.highlight, style: style)
            }
        }
    }
}
