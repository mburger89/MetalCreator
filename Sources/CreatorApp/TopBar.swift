import CreatorEditor
import CreatorKernel
import CreatorSketchEditor
import CreatorStyle
import MetalUI

/// The glass top bar (spec §6.1): the document's name, the Preview menu, Undo, Redo and Export. While a sketch is
/// open it holds the sketch toolbar instead (sketcher spec §8: "Toolbar (glass, top)"), in chrome opaque to the pointer.
struct TopBar: Component {
    let model: AppModel
    @Environment(ThemeStore.self) var themes: ThemeStore?
    /// How far the content starts in so that it clears the window buttons under a hidden title bar (gap M6-c): the
    /// window root passes `AppLayout.topBarClearance` of the window's `titleBarInsets`; zero in a standard window.
    var clearance = Pixels(0)

    var content: some ElementGroup {
        let clearButtons = Edges(top: Pixels(0), right: Pixels(0), bottom: Pixels(0), left: clearance)
        if let sketch = model.sketch {
            SketchChrome { ZStack(alignment: .topLeading) { SketchToolbar(model: sketch.editor) }.padding(clearButtons) }
        } else {
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
                .padding(clearButtons)
            }
        }
    }
}
