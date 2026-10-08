import CreatorGraph
import MetalUI

/// The inspector's header bar in the node's category colour, with its name and status (spec §6.4).
struct InspectorHeaderView: Component {
    let header: InspectorHeader

    var content: some ElementGroup {
        HStack(spacing: Pixels(8)) {
            Text(header.title).font(.headline).foregroundStyle(Palette.textOnAccent.color)
            Spacer()
            StatusBadgeView(state: header.state)
        }
        .padding(Edges(top: Pixels(6), right: Pixels(10), bottom: Pixels(6), left: Pixels(10)))
        .background(Palette.header(for: header.category).color, in: RoundedRectangle(cornerRadius: Pixels(6)))
    }
}
