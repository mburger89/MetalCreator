import CreatorStyle
import MetalUI

/// A node type's row content, shared by the palette, the node library and the library's drag ghost: a
/// category-coloured dot and the type's name, on the field colour while highlighted.
struct PaletteEntryLabel: Component {
    let entry: PaletteEntry
    let isHighlighted: Bool
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let palette = Palette(themes)
        return HStack(spacing: Pixels(6)) {
            Circle().fill(palette.header(for: entry.category).color).frame(width: Pixels(8), height: Pixels(8))
            Text(entry.displayName).font(.callout).foregroundStyle(palette.primaryText.color)
            Spacer()
        }
        .padding(Edges(top: Pixels(0), right: Pixels(6), bottom: Pixels(0), left: Pixels(6)))
        .frame(height: PaletteLayout.rowHeight.px)
        .background(isHighlighted ? palette.field.color : Color.clear, in: RoundedRectangle(cornerRadius: Pixels(4)))
    }
}
