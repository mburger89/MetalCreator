import CreatorEditor
import CreatorStyle
import MetalUI

/// One role: its title, its colour as hex and a swatch of it.
struct ThemeRoleRow: Component {
    let model: ThemeEditorModel
    let role: ThemeRole
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let palette = Palette(themes)
        let colour = model.theme.colors[role]
        return HStack(spacing: ThemeEditorLayout.spacing.px) {
            Text(role.title).font(.callout).foregroundStyle(palette.primaryText.color)
            Spacer()
            Text(colour.hex).font(.caption).foregroundStyle(palette.secondaryText.color)
            ThemeSwatch(colour: colour)
        }
        .frame(height: ThemeEditorLayout.rowHeight.px)
    }
}
