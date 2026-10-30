import CreatorStyle
import MetalUI

/// The window's root (spec §6.1, Themes milestone): the app (`AppRoot`) with the theme editor floating over
/// everything, all drawn in the shown theme, including MetalUI's own controls (`ColorTheme.controlTheme`), so its
/// buttons, fields, menus and pickers match the panels and follow each theme edit at once.
public struct AppWindowRoot: Component {
    public let model: AppModel
    public let input: AppInput
    public let themeEditor: ThemeEditorModel

    public init(model: AppModel, input: AppInput, themeEditor: ThemeEditorModel) {
        self.model = model
        self.input = input
        self.themeEditor = themeEditor
    }

    public var content: some ElementGroup {
        // The root takes the window's size and no more, and what needs more (panels, taller fonts) runs off the bottom. A root
        // that sized itself to its content would be centred by the window's wrapper, which moves an overflowing root up by half
        // the overflow, so the top bar and the drag strip would no longer start where `AppLayout` puts them (the Windows suite's
        // fonts overflowed by 6 points). An overlay does not change its host's size, and a Spacer draws nothing.
        Spacer()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    AppRoot(model: model, input: input)
                    SectionPanelDock(model: model, themeEditorOpen: themeEditor.isOpen)
                    ThemeEditorDock(model: themeEditor,
                                    bottom: ThemeEditorLayout.bottom(dock: model.editor.dock, panelHeight: model.panelHeight))
                }
                // A primary press on anything inside that is not a text field or a click-focusable control resigns the focus
                // (MetalUI C24, gap CT-a), so typing ends on "a press elsewhere" (spec 2026-10-09 section 8). It routes no keys.
                .resignsFocusOnPress()
                .environment(model.themes)
                .theme(model.themes.current.controlTheme)
            }
    }
}
