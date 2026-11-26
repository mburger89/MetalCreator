import CreatorGeometry
import CreatorKernel

/// Composes a sheet's annotations into its picture: each view's centre marks and annotations after its lines, the notes free on
/// the sheet last, then the list of lost ones (plan R13, R15, R25).
struct AnnotationPass {
    let sheet: DrawingSheet
    let standard: DrawingStandard
    let style: DrawingStyle
    let format: NumberFormat
    let remembered: [AnnotationID: LastGood]

    private var annotationStyle: AnnotationStyle { .of(standard) }
    private var height: Double { style.notesHeight(for: sheet.size) }

    func compose(
        view: DrawingView, center: Vector2, scale: Double, content: ViewContent, frame: Rect2D, into picture: inout SheetPicture
    ) {
        var extents = frame
        var mapping: ViewMapping?
        if let projection = content.projection {
            mapping = ViewMapping.of(projection: projection, center: center, scale: scale) ?? ViewMapping(scale: scale, offset: center)
        }
        if view.showsCentreMarks, let projection = content.projection, let mapping {
            let marks = CentreMarkComposer.automatic(
                projection: projection, view: view.id, mapping: mapping,
                styles: CentreMarkComposer.Styles(annotation: annotationStyle, drawing: style))
            picture.strokes += marks
            if let bounds = AnnotationComposer.bounds(of: marks) { extents = extents.union(bounds) }
        }
        let context = AnnotationContext(
            view: view.id, center: center, mapping: mapping, viewFrame: frame, projection: content.projection,
            state: AnnotationViewState.of(content, frame: view.orientation.frame), standard: standard, style: annotationStyle,
            drawingStyle: style, height: height)
        for annotation in sheet.annotations(of: view.id) {
            let (report, pieces) = AnnotationComposer.compose(
                annotation, context: context, format: format, remembered: remembered[annotation.id])
            picture.annotationReports[annotation.id] = report
            picture.strokes += pieces.strokes
            picture.fills += pieces.fills
            picture.texts += pieces.texts
            if let more = pieces.frame { extents = extents.union(more) }
        }
        picture.viewExtents[view.id] = extents
    }

    /// The notes free on the sheet, then `lostAnnotations`.
    func finish(_ picture: inout SheetPicture) {
        let context = AnnotationContext(
            view: nil, center: .zero, mapping: ViewMapping(scale: 1, offset: .zero), viewFrame: Rect2D(min: .zero, max: .zero),
            projection: nil, state: .unlisted(.noPart), standard: standard, style: annotationStyle, drawingStyle: style,
            height: height)
        for annotation in sheet.annotations where annotation.view == nil {
            let (report, pieces) = AnnotationComposer.compose(
                annotation, context: context, format: format, remembered: remembered[annotation.id])
            picture.annotationReports[annotation.id] = report
            picture.strokes += pieces.strokes
            picture.fills += pieces.fills
            picture.texts += pieces.texts
        }
        picture.lostAnnotations = sheet.annotations.filter { picture.annotationReports[$0.id]?.isLost == true }.map(\.id)
    }
}
