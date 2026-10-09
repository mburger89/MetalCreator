import CreatorStyle
import MetalUI

/// The inspector while sketching (sketcher spec §8): the degrees-of-freedom readout or the problem, a refused
/// command's reason, the constraint buttons, the dimensions with their name and value fields, "Expose as input" and
/// driving switches, and the constraints, each removable. Conflicting rows are in the error colour. The host draws it
/// in glass chrome.
public struct SketchInspector: Component {
    let model: SketchEditorModel
    @Environment(ThemeStore.self) var themes: ThemeStore?

    public init(model: SketchEditorModel) {
        self.model = model
    }

    public var content: some ElementGroup {
        let colors = SketchColors(themes)
        return VStack(alignment: .leading, spacing: Pixels(8)) {
            Text(model.statusText).font(.callout).foregroundStyle(model.statusIsProblem ? colors.problem : colors.primary)
            if let refusal = model.refusal {
                Text(refusal).font(.caption).foregroundStyle(colors.warning)
            }
            Text("CONSTRAIN").font(.caption2).foregroundStyle(colors.secondary)
            ConstraintButtons(model: model)
            Text("DIMENSIONS").font(.caption2).foregroundStyle(colors.secondary)
            if model.dimensionRows.isEmpty {
                Text("Pick the Dimension tool (D), then a line, two points or a circle.").font(.caption).foregroundStyle(colors.secondary)
            }
            ForEach(model.dimensionRows, id: \.id) { row in
                DimensionRowView(model: model, row: row)
            }
            Text("CONSTRAINTS").font(.caption2).foregroundStyle(colors.secondary)
            if model.constraintRows.isEmpty {
                Text("No constraints").font(.caption).foregroundStyle(colors.secondary)
            }
            ForEach(model.constraintRows, id: \.id) { row in
                HStack(spacing: Pixels(6)) {
                    Text(row.label).font(.callout).foregroundStyle(row.isConflicting ? colors.problem : colors.primary)
                    Spacer()
                    Button("Remove") { model.remove(.constraint(row.id)) }
                }
            }
        }
        .frame(width: Pixels(280), alignment: .topLeading)
    }
}
