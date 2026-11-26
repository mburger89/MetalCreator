import CreatorDrawing
import MetalUI

/// The inspector for one datum feature symbol (DR-4 R15): its letter, what it stands on, the rules it breaks, why it is lost and
/// Delete.
struct DatumInspector: Component {
    let model: DrawingEditorModel
    let id: AnnotationID
    let datum: DatumFeature
    let report: AnnotationReport?
    let colors: DrawingColors

    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: Pixels(8)) {
            Text("Datum symbol").font(.headline).foregroundStyle(colors.primary.color)
            DrawingRow("Letter", colors: colors) {
                DrawingField(model: model, text: datum.letter, width: 80) { model.setDatumLetter($0, of: id) }
            }
            DrawingRow("Stands", colors: colors) {
                Text(SymbolPageTail.attachmentText(datum.attachment)).font(.callout).foregroundStyle(colors.primary.color)
            }
            SymbolPageTail(model: model, attachment: datum.attachment, report: report, colors: colors)
        }
        .frame(width: drawingInspectorWidth.px)
    }
}

/// What every symbol page ends with: the rule warnings, the reason a lost symbol is lost and how to attach it again, a refusal and
/// Delete.
struct SymbolPageTail: Component {
    let model: DrawingEditorModel
    let attachment: SymbolAttachment
    let report: AnnotationReport?
    let colors: DrawingColors

    /// "On a line" or "On a dimension".
    static func attachmentText(_ attachment: SymbolAttachment) -> String {
        switch attachment {
        case .feature: "On a line"
        case .dimension: "On a dimension"
        }
    }

    /// How a lost symbol is attached again: a click on a line, or through the dimension it hangs on.
    static func reattachText(_ attachment: SymbolAttachment) -> String {
        switch attachment {
        case .feature: DimensionInspector.reattachSentence
        case .dimension: DrawingEditorModel.symbolOnDimensionSentence
        }
    }

    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: Pixels(8)) {
            ForEach((report?.warnings ?? []).indices, id: \.self) { index in
                Text(report?.warnings[index] ?? "").font(.caption).foregroundStyle(colors.warning.color)
            }
            if case .lost(let reason)? = report?.status {
                Text(reason.sentence).font(.caption).foregroundStyle(colors.warning.color)
                Text(Self.reattachText(attachment)).font(.caption).foregroundStyle(colors.secondary.color)
            }
            if let refusal = model.refusal {
                Text(refusal).font(.caption).foregroundStyle(colors.warning.color)
            }
            Button("Delete") { model.deleteSelection() }
        }
    }
}
