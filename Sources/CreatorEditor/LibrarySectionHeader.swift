import CreatorGraph
import CreatorStyle
import MetalUI

/// A node-library category's header: its title in the theme's text-on-accent colour on the category's header
/// colour, the colour its nodes' headers have (spec §6.6).
struct LibrarySectionHeader: Component {
    let category: NodeCategory
    let title: String
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let palette = Palette(themes)
        return HStack(spacing: Pixels(0)) {
            Text(title)
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(palette.textOnAccent.color)
            Spacer()
        }
        .padding(Edges(top: Pixels(0), right: Pixels(6), bottom: Pixels(0), left: Pixels(6)))
        .frame(height: Pixels(18))
        .background(palette.header(for: category).color, in: RoundedRectangle(cornerRadius: Pixels(4)))
    }
}
