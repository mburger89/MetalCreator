import CreatorGraph
import CreatorStyle
import MetalUI

/// The inspector's header bar in the node's category colour, with its name and status (spec §6.4).
struct InspectorHeaderView: Component {
    let header: InspectorHeader
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let palette = Palette(themes)
        return HStack(spacing: Pixels(8)) {
            Text(header.title).font(.headline).foregroundStyle(palette.textOnAccent.color)
            Spacer()
            StatusBadgeView(state: header.state)
        }
        .padding(Edges(top: Pixels(6), right: Pixels(10), bottom: Pixels(6), left: Pixels(10)))
        .background(palette.header(for: header.category).color, in: RoundedRectangle(cornerRadius: Pixels(6)))
    }
}
