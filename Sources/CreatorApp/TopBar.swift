import CreatorEditor
import CreatorKernel
import CreatorStyle
import MetalUI

/// The glass top bar (spec §6.1): the document's name, the Preview menu, Undo, Redo and Export.
struct TopBar: Component {
    let model: AppModel
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        GlassPanel {
            HStack(spacing: Pixels(10)) {
                Text(model.isEdited ? "\(model.displayName) — Edited" : model.displayName)
                    .font(.headline)
                    .foregroundStyle(Palette(themes).primaryText.color)
                Spacer()
                Picker("Preview", selection: Binding(get: { model.previewMode }, set: { model.previewMode = $0 })) {
                    ForEach(PreviewMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                Button("Undo") { model.undo() }
                    .disabled(!model.document.canUndo)
                Button("Redo") { model.redo() }
                    .disabled(!model.document.canRedo)
                Menu("Export") {
                    Button("STEP…") { model.withFilePicker { await model.exportDocument(.step, using: $0) } }
                    Button("STL…") { model.withFilePicker { await model.exportDocument(.stl, using: $0) } }
                }
            }
        }
    }
}
