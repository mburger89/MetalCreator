import CreatorStyle
import MetalUI

/// A tree's shape in the inspector, with a button that opens the list of its branches: each path and how many items
/// it holds. The list is cut after `TreeShapeRow.maximumEntries` branches.
struct TreeShapeView: Component {
    let row: TreeShapeRow
    let model: EditorModel
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let palette = Palette(themes)
        return VStack(alignment: .leading, spacing: Pixels(4)) {
            LabeledRow(label: row.label) {
                Spacer()
                Text(row.summary).font(.callout).foregroundStyle(palette.secondaryText.color)
            }
            Button(row.isExpanded ? "Hide paths" : "Show paths") { model.toggleShapeList(row.key) }
            if row.isExpanded {
                ForEach(row.entries, id: \.path) { entry in
                    HStack(spacing: Pixels(8)) {
                        Text(entry.path).font(.caption).foregroundStyle(palette.primaryText.color)
                        Spacer()
                        Text(Self.countText(entry.count)).font(.caption).foregroundStyle(palette.secondaryText.color)
                    }
                }
                if row.hiddenCount > 0 {
                    Text("and \(row.hiddenCount.formatted(.number.locale(ValueText.locale))) more").font(.caption)
                        .foregroundStyle(palette.secondaryText.color)
                }
            }
        }
    }

    /// "1 item", "8 items".
    static func countText(_ count: Int) -> String {
        "\(count.formatted(.number.locale(ValueText.locale))) \(count == 1 ? "item" : "items")"
    }
}
