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
    /// What the rules of geometric tolerancing need, made once per compose (plan R8, R18).
    let rules: GDTRules.Context
    /// The drawing's item numbers, made once per compose from the document and the facts' part names (DR-5 R5).
    let items: [NumberedItem]

    private var annotationStyle: AnnotationStyle { .of(standard) }
    private var height: Double { style.notesHeight(for: sheet.size) }

    func compose(
        view: DrawingView, center: Vector2, scale: Double, content: ViewContent, frame: Rect2D, into picture: inout SheetPicture
    ) {
        var extents = frame
        var mapping: ViewMapping?
        if content.projection != nil {
            mapping = ViewMapping.of(content: content, center: center, scale: scale) ?? ViewMapping(scale: scale, offset: center)
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
            drawingStyle: style, height: height, isPictorial: sheet.isPictorial(view), items: items,
            viewSource: view.source)
        let annotations = sheet.annotations(of: view.id)
        // R11's order: everything not on a dimension, then frames on dimensions, then datum symbols on dimensions, so a hanging
        // datum sits below the frames on the same dimension.
        for annotation in annotations where !Self.isOnDimension(annotation) {
            let (report, pieces) = AnnotationComposer.compose(
                annotation, context: context, format: format, remembered: remembered[annotation.id])
            add(report, pieces, of: annotation, extents: &extents, to: &picture)
        }
        var bottoms: [AnnotationID: Double] = [:]
        for kind in [SymbolKind.frame, .datum] {
            for annotation in annotations where annotation.symbolKind == kind {
                guard case .dimension(let host)? = annotation.symbolAttachment else { continue }
                let made = AnnotationComposer.composeOnDimension(
                    annotation, host: picture.annotationReports[host], context: context, format: format, below: bottoms[host])
                bottoms[host] = made.bottom
                add(made.report, made.pieces, of: annotation, extents: &extents, to: &picture)
            }
        }
        picture.viewExtents[view.id] = extents
    }

    private static func isOnDimension(_ annotation: DrawingAnnotation) -> Bool {
        if case .dimension? = annotation.symbolAttachment { true } else { false }
    }

    /// Records a composed annotation: its report (with the rules' warnings for a symbol) and its pieces.
    private func add(
        _ report: AnnotationReport, _ pieces: AnnotationPieces, of annotation: DrawingAnnotation, extents: inout Rect2D,
        to picture: inout SheetPicture
    ) {
        var report = report
        if annotation.symbolKind != nil { report.warnings = GDTRules.warnings(for: annotation, context: rules) }
        picture.annotationReports[annotation.id] = report
        picture.strokes += pieces.strokes
        picture.fills += pieces.fills
        picture.texts += pieces.texts
        if let more = pieces.frame { extents = extents.union(more) }
    }

    /// The notes free on the sheet, then `lostAnnotations` and `checkedAnnotations`.
    func finish(_ picture: inout SheetPicture) {
        let context = AnnotationContext(
            view: nil, center: .zero, mapping: ViewMapping(scale: 1, offset: .zero), viewFrame: Rect2D(min: .zero, max: .zero),
            projection: nil, state: .unlisted(.noPart), standard: standard, style: annotationStyle, drawingStyle: style,
            height: height, items: items)
        for annotation in sheet.annotations where annotation.view == nil {
            let (report, pieces) = AnnotationComposer.compose(
                annotation, context: context, format: format, remembered: remembered[annotation.id])
            picture.annotationReports[annotation.id] = report
            picture.strokes += pieces.strokes
            picture.fills += pieces.fills
            picture.texts += pieces.texts
        }
        picture.lostAnnotations = sheet.annotations.filter { picture.annotationReports[$0.id]?.isLost == true }.map(\.id)
        picture.checkedAnnotations = sheet.annotations.filter {
            !(picture.annotationReports[$0.id]?.warnings.isEmpty ?? true)
        }.map(\.id)
    }
}
