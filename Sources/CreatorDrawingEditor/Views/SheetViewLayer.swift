import CreatorDrawing
import CreatorGeometry
import CreatorStyle
import MetalUI

/// One view's projected linework on the sheet (plan R27): its strokes (projected lines, hatching, marks), in paper space, under the view's
/// annotations (`SheetAnnotationLayer`). `.equatable()` where the canvas builds it. `==` compares the bucket's `revision` in
/// place of its arrays (drawings speed R4) and every other stored property, so a pan, or a change to another view or to this
/// view's annotations, skips it; `SheetViewEqualityTests` fails when a property gains no variant.
struct SheetViewLayer: Component, Equatable {
    let id: ViewID
    let bucket: SheetLayers.Bucket
    let zoom: Double
    let paperHeight: Double
    /// A projection is being made: the old one stays drawn at 40 % (plan R19).
    let isPending: Bool
    let colors: DrawingColors
    let style: DrawingStyle

    nonisolated static func == (lhs: SheetViewLayer, rhs: SheetViewLayer) -> Bool {
        lhs.id == rhs.id && lhs.bucket.revision == rhs.bucket.revision && lhs.zoom == rhs.zoom
            && lhs.paperHeight == rhs.paperHeight && lhs.isPending == rhs.isPending && lhs.colors == rhs.colors
            && lhs.style == rhs.style
    }

    var content: some ElementGroup {
        ZStack(alignment: .topLeading) {
            SheetStrokeGroups(
                strokes: bucket.strokes, zoom: zoom, paperHeight: paperHeight, ink: colors.ink, style: style,
                warning: colors.warning)
        }
        .opacity(isPending ? 0.4 : 1)
    }
}
