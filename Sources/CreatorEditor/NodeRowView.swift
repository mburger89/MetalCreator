import CreatorStyle
import MetalUI

/// One body row: the socket label, and an unwired input's value at the trailing edge.
struct NodeRowView: Component {
    let row: NodeRowModel
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let palette = Palette(themes)
        return HStack(spacing: Pixels(6)) {
            if row.isInput {
                Text(row.label).font(.caption).foregroundStyle(palette.primaryText.color)
                Spacer()
                Text(row.value ?? "").font(.caption).foregroundStyle(palette.secondaryText.color)
            } else {
                Spacer()
                Text(row.label).font(.caption).foregroundStyle(palette.primaryText.color)
            }
        }
        .frame(height: NodeLayout.rowHeight.px)
    }
}
