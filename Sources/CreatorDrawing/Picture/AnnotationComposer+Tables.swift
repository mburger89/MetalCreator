import CreatorGeometry
import CreatorKernel

extension AnnotationComposer {
    /// The parts list (DR-5 R7): free on the sheet, standing on `bottomRight` or on the title block.
    static func composeTable(
        _ annotation: DrawingAnnotation, partsList: PartsList, context: AnnotationContext
    ) -> (report: AnnotationReport, pieces: AnnotationPieces) {
        let corner = partsList.bottomRight ?? context.blockTopRight
        let drawing = PartsListLayout.draw(
            context.items, facts: context.partFacts, bottomRight: corner, standard: context.standard, h: context.height)
        return tableResult(drawing, label: "Parts list", annotation: annotation, context: context)
    }

    /// The revision table (DR-5 R9): hanging from `topRight` or from the frame's inside top right.
    static func composeTable(
        _ annotation: DrawingAnnotation, revisions table: RevisionTable, context: AnnotationContext
    ) -> (report: AnnotationReport, pieces: AnnotationPieces) {
        let corner = table.topRight ?? context.frameTopRight
        let drawing = RevisionTableLayout.draw(table, topRight: corner, standard: context.standard, h: context.height)
        return tableResult(drawing, label: "Revision table", annotation: annotation, context: context)
    }

    /// Lines on the frame layer (the outline at `DrawingStyle.frame`, the rest at `zone`), the header's labels on the frame layer
    /// and the cells on the text layer.
    private static func tableResult(
        _ drawing: AnnotationDrawing, label: String, annotation: DrawingAnnotation, context: AnnotationContext
    ) -> (report: AnnotationReport, pieces: AnnotationPieces) {
        let style = context.drawingStyle
        var out = AnnotationPieces()
        for box in drawing.boxes {
            out.strokes.append(
                SheetStroke(segments: [.polyline(box)], width: style.frame, layer: .frame, annotation: annotation.id))
        }
        for segment in drawing.segments {
            out.strokes.append(
                SheetStroke(segments: [segment], width: style.zone, layer: .frame, annotation: annotation.id))
        }
        for (index, text) in drawing.texts.enumerated() {
            out.texts.append(
                SheetText(
                    run: text.run, original: text.original, origin: text.origin, height: text.height,
                    layer: index < drawing.labelCount ? .frame : .text, angle: text.angle, annotation: annotation.id))
        }
        out.frame = drawing.frame
        let report = AnnotationReport(status: .held, label: label, frame: drawing.frame)
        return (report, out)
    }
}
