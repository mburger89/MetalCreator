import CreatorEditor
import CreatorStyle
import MetalUI

/// One role: its title, its colour as hex, and MetalUI's colour well, which opens its colour panel and writes each
/// move to the theme (`ThemeEditorModel.colorBinding(for:)`, saved and shown at once). Opacity is offered only where
/// the role is translucent by design; a built-in's wells are disabled. The well is untitled (the role's title is its
/// own text), so it carries the title as its accessibility label: VoiceOver reads "Selection", not an unnamed well
/// (MetalUI's `C1`: an untitled well has no label; the label distributes from the picker's box to the well, AB-T).
struct ThemeRoleRow: Component {
    let model: ThemeEditorModel
    let role: ThemeRole
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let palette = Palette(themes)
        return HStack(spacing: ThemeEditorLayout.spacing.px) {
            Text(role.title).font(.callout).foregroundStyle(palette.primaryText.color)
            Spacer()
            Text(model.theme.colors[role].hex).font(.caption).foregroundStyle(palette.secondaryText.color)
            ColorPicker("", selection: model.colorBinding(for: role), supportsOpacity: role.allowsOpacity)
                .accessibilityLabel(role.title)
                .disabled(!model.isEditable)
        }
        .frame(height: ThemeEditorLayout.rowHeight.px)
    }
}
