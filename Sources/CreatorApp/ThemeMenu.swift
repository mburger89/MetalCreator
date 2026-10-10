import CreatorStyle
import MetalUI

/// View ▸ Theme (spec §6.6, Themes milestone): the built-in themes, then the person's own, each with a checkmark on
/// the one shown and shown at once when chosen, then Edit Themes…, which opens the theme editor. Rebuilt each time
/// the menu opens, so a new, renamed or deleted theme is listed as it is.
enum ThemeMenu {
    /// The menu's groups of themes, divided in the menu: the built-ins, then the custom themes if there are any.
    /// (What the menu lists is tested here: MetalUI can't evaluate menu content outside itself, gap TH-a.)
    @MainActor
    static func sections(_ themes: ThemeStore) -> [[ColorTheme]] {
        themes.customs.isEmpty ? [themes.builtIns] : [themes.builtIns, themes.customs]
    }

    @MainActor
    @MenuContentBuilder
    static func items(_ editor: ThemeEditorModel) -> MenuItems {
        for section in sections(editor.themes) {
            for theme in section {
                // Choosing the checked theme writes `false`; selecting it again changes nothing.
                Toggle(theme.name, isOn: Binding(get: { editor.theme.id == theme.id },
                                                 set: { _ in editor.select(theme.id) }))
            }
            Divider()
        }
        Button("Edit Themes…") { editor.open() }
    }
}
