import CreatorDrawing
import MetalUI

/// The inspector for what is selected among a sheet's annotations (plan R20): one dimension, hole callout, note, centre mark or
/// centre line gets its own page; several get "N items selected" and Delete.
struct AnnotationInspector: Component {
    let model: DrawingEditorModel
    let sheet: DrawingSheet
    let colors: DrawingColors
    /// How many views are selected with them.
    var views = 0

    var content: some ElementGroup {
        let chosen = sheet.annotations.filter { model.selectedAnnotations.contains($0.id) }
        if chosen.count + views > 1 {
            VStack(alignment: .leading, spacing: Pixels(8)) {
                Text("\(chosen.count + views) items selected").font(.headline).foregroundStyle(colors.primary.color)
                Button("Delete") { model.deleteSelection() }
            }
            .frame(width: drawingInspectorWidth.px)
        } else if let one = chosen.first {
            page(one)
        }
    }

    @ElementBuilder
    private func page(_ annotation: DrawingAnnotation) -> some ElementGroup {
        let report = model.picture?.annotationReports[annotation.id]
        switch annotation.kind {
        case .dimension(let dimension):
            DimensionInspector(model: model, id: annotation.id, dimension: dimension, report: report, colors: colors)
        case .holeCallout(let callout):
            calloutPage(annotation.id, callout, report)
        case .note(let note):
            NoteInspector(model: model, id: annotation.id, note: note, colors: colors)
        case .centreMark:
            deletePage("Centre mark")
        case .centreLine:
            deletePage("Centre line")
        case .datumFeature(let datum):
            DatumInspector(model: model, id: annotation.id, datum: datum, report: report, colors: colors)
        case .featureControl(let frame):
            FrameInspector(model: model, id: annotation.id, frame: frame, report: report, colors: colors)
        case .surfaceTexture(let texture):
            SurfaceInspector(model: model, id: annotation.id, texture: texture, report: report, colors: colors)
        case .balloon, .partsList, .revisionTable:
            deletePage("Annotation")  // DR-5 Task 10
        }
    }

    private func calloutPage(_ id: AnnotationID, _ callout: HoleCallout, _ report: AnnotationReport?) -> some ElementGroup {
        let lines = report?.current?.lines ?? []
        return VStack(alignment: .leading, spacing: Pixels(8)) {
            Text("Hole callout").font(.headline).foregroundStyle(colors.primary.color)
            ForEach(lines.indices, id: \.self) { index in
                Text(lines[index]).font(.callout).foregroundStyle(colors.primary.color)
            }
            if case .lost(let reason)? = report?.status {
                Text(reason.sentence).font(.caption).foregroundStyle(colors.warning.color)
                Text(DimensionInspector.reattachSentence).font(.caption).foregroundStyle(colors.secondary.color)
            }
            DrawingRow("Prefix", colors: colors) {
                DrawingField(model: model, text: callout.prefix, width: 150) { model.setPrefix($0, of: id) }
            }
            DrawingRow("Suffix", colors: colors) {
                DrawingField(model: model, text: callout.suffix, width: 150) { model.setSuffix($0, of: id) }
            }
            if let refusal = model.refusal {
                Text(refusal).font(.caption).foregroundStyle(colors.warning.color)
            }
        }
        .frame(width: drawingInspectorWidth.px)
    }

    private func deletePage(_ title: String) -> some ElementGroup {
        VStack(alignment: .leading, spacing: Pixels(8)) {
            Text(title).font(.headline).foregroundStyle(colors.primary.color)
            Button("Delete") { model.deleteSelection() }
        }
        .frame(width: drawingInspectorWidth.px)
    }
}
