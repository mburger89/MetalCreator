import CreatorDrawing
import CreatorGeometry
import CreatorStyle
import MetalUI

/// One view's annotations and notices over its linework (`SheetViewLayer`), the hovered line and the selection outline, in paper
/// space. A view's annotations draw faded with its linework while it is being projected; its notices stay at full strength. `==`
/// compares the bucket's `revision` in place of its arrays, so a pan, or a change to another view or to this view's linework,
/// skips it; a dimension drag evaluates only this layer of its view and the selection layer.
struct SheetAnnotationLayer: Component, Equatable {
    let id: ViewID
    let bucket: SheetLayers.Bucket
    let frame: Rect2D
    let zoom: Double
    let paperHeight: Double
    let isPending: Bool
    let isSelected: Bool
    /// The one stroke of this view the pointer is near, redrawn in the highlight colour.
    let hovered: SheetStroke?
    let colors: DrawingColors
    let style: DrawingStyle

    nonisolated static func == (lhs: SheetAnnotationLayer, rhs: SheetAnnotationLayer) -> Bool {
        lhs.id == rhs.id && lhs.bucket.revision == rhs.bucket.revision && lhs.frame == rhs.frame && lhs.zoom == rhs.zoom
            && lhs.paperHeight == rhs.paperHeight && lhs.isPending == rhs.isPending && lhs.isSelected == rhs.isSelected
            && lhs.hovered == rhs.hovered && lhs.colors == rhs.colors && lhs.style == rhs.style
    }

    var content: some ElementGroup {
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                SheetStrokeGroups(
                    strokes: bucket.strokes, zoom: zoom, paperHeight: paperHeight, ink: colors.ink, style: style,
                    fills: bucket.fills, warning: colors.warning)
                SheetTexts(
                    texts: bucket.texts.filter { !$0.isNotice }, zoom: zoom, paperHeight: paperHeight, ink: colors.ink,
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
                texts: bucket.texts.filter(\.isNotice), zoom: zoom, paperHeight: paperHeight, ink: colors.ink,
                warning: colors.warning)
        }
    }
}
