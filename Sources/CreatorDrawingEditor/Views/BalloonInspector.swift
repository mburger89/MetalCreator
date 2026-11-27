import CreatorDrawing
import MetalUI

/// A balloon's page (DR-5 R4, R5): which item it names, why it is lost, how to re-attach it, and Delete.
struct BalloonInspector: Component {
    let model: DrawingEditorModel
    let sheet: DrawingSheet
    let annotation: DrawingAnnotation
    let balloon: Balloon
    let report: AnnotationReport?
    let colors: DrawingColors

    /// "Item 2 · Right", or "Item ? · Right" for a part no item lists.
    static func itemText(number: Int?, name: String?) -> String {
        "Item \(number.map(String.init) ?? "?") · \(name ?? "?")"
    }

    /// The view the balloon is on; none when it has no view, and then no item row is shown.
    static func view(of annotation: DrawingAnnotation, in sheet: DrawingSheet) -> DrawingView? {
        annotation.view.flatMap { sheet.view($0) }
    }

    var content: some ElementGroup {
        let view = Self.view(of: annotation, in: sheet)
        let part = view.map { balloon.part(in: $0) } ?? balloon.leader.target.part
        let names = model.partNames
        let number = part.flatMap { PartItems.numbered(model.document, names: names).number(of: $0) }
        VStack(alignment: .leading, spacing: Pixels(8)) {
            Text("Balloon").font(.headline).foregroundStyle(colors.primary.color)
            if view != nil {
                Text(Self.itemText(number: number, name: part.flatMap { names[$0] })).font(.callout)
                    .foregroundStyle(colors.primary.color)
            }
            if case .lost(let reason)? = report?.status {
                Text(reason.sentence).font(.caption).foregroundStyle(colors.warning.color)
                Text(DimensionInspector.reattachSentence).font(.caption).foregroundStyle(colors.secondary.color)
            }
            if let refusal = model.refusal {
                Text(refusal).font(.caption).foregroundStyle(colors.warning.color)
            }
            Button("Delete") { model.deleteSelection() }
        }
        .frame(width: drawingInspectorWidth.px)
    }
}
