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

    var content: some ElementGroup {
        let part = sheet.view(annotation.view ?? ViewID()).map { balloon.part(in: $0) } ?? balloon.leader.target.part
        let names = model.partNames
        let number = part.flatMap { PartItems.numbered(model.document, names: names).number(of: $0) }
        VStack(alignment: .leading, spacing: Pixels(8)) {
            Text("Balloon").font(.headline).foregroundStyle(colors.primary.color)
            Text(Self.itemText(number: number, name: part.flatMap { names[$0] })).font(.callout)
                .foregroundStyle(colors.primary.color)
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
