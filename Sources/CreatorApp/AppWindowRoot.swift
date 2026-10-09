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
        ZStack(alignment: .topLeading) {
            AppRoot(model: model, input: input)
            ThemeEditorDock(model: themeEditor,
                            bottom: ThemeEditorLayout.bottom(dock: model.editor.dock, panelHeight: model.panelHeight))
        }
        .environment(model.themes)
        .theme(model.themes.current.controlTheme)
    }
}
