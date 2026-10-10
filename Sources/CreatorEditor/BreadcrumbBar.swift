import CreatorStyle
import MetalUI

/// The graph panel's title as breadcrumbs, "Graph › Rib › Hole pattern" (groups spec §6): each level but the one shown
/// is a button that goes back out to it (`EditorModel.goToLevel(_:)`), and the level shown is plain text. On the top
/// level it is just "Graph", as the title always was.
struct BreadcrumbBar: Component {
    let model: EditorModel
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let palette = Palette(themes)
        let crumbs = model.breadcrumbs
        return HStack(spacing: Pixels(4)) {
            ForEach(crumbs, id: \.depth) { crumb in
                if crumb.depth == crumbs.count - 1 {
                    Text(crumb.title).font(.headline).foregroundStyle(palette.primaryText.color)
                } else {
                    Button(crumb.title) { model.goToLevel(crumb.depth) }
                        .buttonStyle(.plain)
                        .help("Back to \(crumb.title) (⌘↑)")
                        .foregroundStyle(palette.secondaryText.color)
                    Text("›").font(.headline).foregroundStyle(palette.secondaryText.color)
                }
            }
        }
    }
}
