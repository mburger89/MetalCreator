import MetalUI

/// One body row: the socket label, and an unwired input's value at the trailing edge.
struct NodeRowView: Component {
    let row: NodeRowModel

    var content: some ElementGroup {
        HStack(spacing: Pixels(6)) {
            if row.isInput {
                Text(row.label).font(.caption).foregroundStyle(Palette.primaryText.color)
                Spacer()
                Text(row.value ?? "").font(.caption).foregroundStyle(Palette.secondaryText.color)
            } else {
                Spacer()
                Text(row.label).font(.caption).foregroundStyle(Palette.primaryText.color)
            }
        }
        .frame(height: NodeLayout.rowHeight.px)
    }
}
