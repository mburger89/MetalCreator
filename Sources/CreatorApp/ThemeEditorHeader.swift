import CreatorEditor
import CreatorStyle
import MetalUI

/// "Themes" and Done (Escape), which commits a typed name and closes the editor.
struct ThemeEditorHeader: Component {
    let model: ThemeEditorModel
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        HStack(spacing: ThemeEditorLayout.spacing.px) {
            Text("Themes").font(.headline).foregroundStyle(Palette(themes).primaryText.color)
            Spacer()
            Button("Done") { model.close() }
                .keyboardShortcut(.escape, modifiers: [])
        }
    }
}
