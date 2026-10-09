import CreatorKernel
import MetalUI

/// The menu bar (spec §6.1): File's New, Open…, Save, Save As… and the exports, Edit's Undo and Redo bound to
/// the document (`AppModel.undo()`, which commits a typed value first), and View ▸ Theme (`ThemeMenu`: every theme
/// with a checkmark on the current one, and Edit Themes…, spec §6.6). Commands run when nothing in the window claims
/// their key first (a focused field keeps its own editing keys).
public enum AppCommands {
    @MainActor
    public static func install(on app: App, model: AppModel, themeEditor: ThemeEditorModel) {
        app.commands {
            CommandGroup(replacing: .newItem) {
                Button("New") { model.newDocument() }
                    .keyboardShortcut("n")
                Button("Open…") { model.withFilePicker { await model.openDocument(using: $0) } }
                    .keyboardShortcut("o")
                Button("Save") { model.withFilePicker { await model.saveDocument(using: $0) } }
                    .keyboardShortcut("s")
                Button("Save As…") { model.withFilePicker { await model.saveDocumentAs(using: $0) } }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Export STEP…") { model.withFilePicker { await model.exportDocument(.step, using: $0) } }
                    .keyboardShortcut("e")
                Button("Export STL…") { model.withFilePicker { await model.exportDocument(.stl, using: $0) } }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { model.undo() }
                    .keyboardShortcut("z")
                    .disabled(!model.document.canUndo)
                Button("Redo") { model.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!model.document.canRedo)
            }
            // MetalUI puts a command menu before Window (it builds no View menu of its own).
            CommandMenu("View") {
                Menu("Theme") { ThemeMenu.items(themeEditor) }
            }
        }
    }
}
