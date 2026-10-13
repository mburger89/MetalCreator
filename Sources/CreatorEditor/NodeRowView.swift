import CreatorStyle
import MetalUI

/// One body row: the socket label, and an unwired input's value at the trailing edge.
struct NodeRowView: Component, Equatable {
    let row: NodeRowModel
    let palette: Palette

    var content: some ElementGroup {
        HStack(spacing: Pixels(6)) {
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
