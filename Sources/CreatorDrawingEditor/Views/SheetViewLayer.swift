import CreatorDrawing
import CreatorGeometry
import CreatorStyle
import MetalUI

/// One view on the sheet (plan R27): its strokes, arrowheads and lettering, the selection outline and the hovered line, in paper space.
/// `.equatable()` where the canvas builds it, and `==` covers every stored property (the synthesized one does;
/// `SheetViewEqualityTests` fails when a property gains no variant), so a pan, or a change to another view, skips it.
struct SheetViewLayer: Component, Equatable {
    let id: ViewID
    let strokes: [SheetStroke]
    let texts: [SheetText]
    let fills: [SheetFill]
    let frame: Rect2D
    let zoom: Double
    let paperHeight: Double
    /// A projection is being made: the old one stays drawn at 40 % (plan R19).
    let isPending: Bool
    let isSelected: Bool
    /// The one stroke of this view the pointer is near, redrawn in the highlight colour.
    let hovered: SheetStroke?
    let colors: DrawingColors
    let style: DrawingStyle

    var content: some ElementGroup {
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                SheetStrokeGroups(
                    strokes: strokes, zoom: zoom, paperHeight: paperHeight, ink: colors.ink, style: style, fills: fills,
                    warning: colors.warning)
                SheetTexts(
                    texts: texts.filter { !$0.isNotice }, zoom: zoom, paperHeight: paperHeight, ink: colors.ink,
                    warning: colors.warning)
                if let hovered {
                    SheetStrokeGroups(
                        strokes: [hovered], zoom: zoom, paperHeight: paperHeight, ink: colors.highlight, style: style)
                }
                if isSelected {
                    let box = frame.insetBy(-1)
                    Rectangle().strokeBorder(colors.highlight.color, lineWidth: Pixels(1))
                        .frame(width: (box.width * zoom).px, height: (box.height * zoom).px)
                        .offset(x: (box.min.x * zoom).px, y: ((paperHeight - box.max.y) * zoom).px)
                }
            }
            .opacity(isPending ? 0.4 : 1)
            // The view's problem and warnings stay at full strength over the faded lines.
            SheetTexts(
                texts: texts.filter(\.isNotice), zoom: zoom, paperHeight: paperHeight, ink: colors.ink, warning: colors.warning)
        }
    }
}
