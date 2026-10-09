import MetalUI

/// The constraint buttons (sketcher spec §8), three to a row, each enabled when the selection fits it and saying
/// what to select in its tooltip.
struct ConstraintButtons: Component {
    let model: SketchEditorModel
    static let perRow = 3

    var content: some ElementGroup {
        let available = model.availableConstraints
        let kinds = SketchConstraintKind.allCases
        return VStack(alignment: .leading, spacing: Pixels(4)) {
            ForEach(Array(stride(from: 0, to: kinds.count, by: Self.perRow)), id: \.self) { start in
                HStack(spacing: Pixels(4)) {
                    ForEach(kinds[start..<min(start + Self.perRow, kinds.count)], id: \.self) { kind in
                        Button(kind.title) { model.addConstraint(kind) }
                            .help(kind.hint)
                            .disabled(!available.contains(kind))
                    }
                }
            }
        }
    }
}
