import CreatorStyle
import MetalUI

/// One dimension: kind, name field, value field, then "Expose as input", Driving and Remove.
struct DimensionRowView: Component {
    let model: SketchEditorModel
    let row: DimensionRow
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let colors = SketchColors(themes)
        return VStack(alignment: .leading, spacing: Pixels(4)) {
            HStack(spacing: Pixels(6)) {
                Text(row.kind).font(.callout).foregroundStyle(row.isConflicting ? colors.problem : colors.primary)
                DimensionField(text: row.name, width: 64) { model.rename(row.id, to: $0) }
                DimensionField(text: row.value, width: 80) { model.setValue($0, of: row.id) }
            }
            HStack(spacing: Pixels(6)) {
                Toggle("Expose as input", isOn: Binding(get: { row.isExposed }, set: { model.setExposed($0, of: row.id) }))
                Toggle("Driving", isOn: Binding(get: { row.isDriving }, set: { model.setDriving($0, of: row.id) }))
                Spacer()
                Button("Remove") { model.remove(.dimension(row.id)) }
            }
        }
    }
}
