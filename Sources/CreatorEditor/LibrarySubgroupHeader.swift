import CreatorStyle
import MetalUI

/// A sub-group's heading in the node library: quiet caption text in the secondary colour, under the category's coloured
/// header. Not interactive.
struct LibrarySubgroupHeader: Component {
    let title: String
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        HStack(spacing: Pixels(0)) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Palette(themes).secondaryText.color)
            Spacer()
        }
        .padding(Edges(top: Pixels(0), right: Pixels(6), bottom: Pixels(0), left: Pixels(6)))
        .frame(height: PaletteLayout.rowHeight.px)
    }
}
