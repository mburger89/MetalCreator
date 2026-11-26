import CreatorDrawing
import CreatorKernel
import MetalUI

/// The view inspector's PARTS rows for an assembly view (DR-5 R1): a Show toggle for every Output in the model, then for every part
/// of the view that is no longer in the model, named "\(name) (removed)" from the facts ("? (removed)" with none), shown on so it
/// can be unticked. Turning off the last part is refused in the model's words.
struct PartsSection: Component {
    let model: DrawingEditorModel
    let view: DrawingView
    let colors: DrawingColors

    struct Row: Hashable {
        var part: NodeID
        var title: String
    }

    /// The rows in order: the model's Outputs, then the view's removed parts.
    static func rows(of view: DrawingView, sources: [DrawingSourceOption], facts: [NodeID: PartFacts], remembered: [NodeID: String])
        -> [Row] {
        var rows = sources.map { Row(part: $0.id, title: $0.name) }
        let known = Set(sources.map(\.id))
        for part in view.outputs where !known.contains(part) {
            rows.append(Row(part: part, title: "\(facts[part]?.name ?? remembered[part] ?? "?") (removed)"))
        }
        return rows
    }

    var content: some ElementGroup {
        let rows = Self.rows(of: view, sources: model.sources, facts: model.partFacts, remembered: model.rememberedPartNames)
        let shown = Set(view.outputs)
        VStack(alignment: .leading, spacing: Pixels(4)) {
            Text("PARTS").font(.caption2).foregroundStyle(colors.secondary.color)
            ForEach(rows, id: \.part.rawValue) { row in
                Toggle(
                    row.title,
                    isOn: Binding(get: { shown.contains(row.part) }, set: { model.setPart(row.part, shown: $0, of: view.id) }))
            }
        }
    }
}
