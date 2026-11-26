import CreatorKernel
import MetalUI

/// The menu bar (spec §6.1): File's New, Open…, Save, Save As… and the exports, Edit's Undo and Redo bound to
/// the document (`AppModel.undo()`, which commits a typed value first), titled "Undo Add Note" by the step
/// (`AppModel.undoTitle`, `redoTitle`), and View ▸ Units and Precision (`UnitsMenu`) and View ▸ Theme (`ThemeMenu`: every theme
/// with a checkmark on the current one, and Edit Themes…, spec §6.6). Commands run when nothing in the window claims
/// their key first (a focused field keeps its own editing keys).
public enum AppCommands {
    @MainActor
    public static func install(on app: App, model: AppModel, themeEditor: ThemeEditorModel) {
        app.commands {
            #if os(macOS)
            CommandGroup(after: .appInfo) { aiConnectionsItem(model) }
            #endif
            CommandGroup(replacing: .newItem) {
                Button("New") { model.newDocument() }
                    .keyboardShortcut("n")
                Button("Open…") { model.withFilePicker { await model.openDocument(using: $0) } }
                    .keyboardShortcut("o")
                importItems(model)
                Button("Save") { model.withFilePicker { await model.saveDocument(using: $0) } }
                    .keyboardShortcut("s")
                Button("Save As…") { model.withFilePicker { await model.saveDocumentAs(using: $0) } }
                    .keyboardShortcut("s", modifiers: [.primary, .shift])
                Button("Export STEP…") { model.withFilePicker { await model.exportDocument(.step, using: $0) } }
                    .keyboardShortcut("e")
                Button("Export STL…") { model.withFilePicker { await model.exportDocument(.stl, using: $0) } }
                    .keyboardShortcut("e", modifiers: [.primary, .shift])
                Button("Export 3MF…") { model.withFilePicker { await model.exportDocument(.threeMF, using: $0) } }
                drawingExportItems(model)
                #if !os(macOS)
                aiConnectionsItem(model)
                #endif
            }
            CommandGroup(replacing: .undoRedo) {
                Button(model.undoTitle) { model.undo() }
                    .keyboardShortcut("z")
                    .disabled(!model.document.canUndo)
                Button(model.redoTitle) { model.redo() }
                    .keyboardShortcut("z", modifiers: [.primary, .shift])
                    .disabled(!model.document.canRedo)
            }
            // MetalUI puts a command menu before Window (it builds no View menu of its own).
            CommandMenu("View") { viewItems(model, themeEditor: themeEditor) }
        }
    }

    /// The View menu: Theme, Units and Precision, the viewport's items (disabled in Drawing, plan R28) and the mode switch.
    @MainActor
    @MenuContentBuilder
    static func viewItems(_ model: AppModel, themeEditor: ThemeEditorModel) -> MenuItems {
        Menu("Theme") { ThemeMenu.items(themeEditor) }
        Menu("Units") { UnitsMenu.unitItems(model) }
        Menu("Precision") { UnitsMenu.precisionItems(model) }
        // The sheet is not the 3D view: its items are disabled in Drawing (plan R28).
        Button(model.document.section?.isOn == true ? "Hide Section" : "Show Section") {
            model.setSection(model.document.section?.isOn != true)
        }
        .disabled(model.mode == .drawing)
        Button("Flip Section") { model.flipSection() }
            .disabled(model.document.section?.isOn != true || model.mode == .drawing)
        Button(model.measure == nil ? "Measure" : "Stop Measuring") { model.setMeasure(model.measure == nil) }
            .disabled(model.sketch != nil || model.pick != nil || model.mode == .drawing)
        Button(model.document.zebra?.isOn == true ? "Hide Zebra Stripes" : "Show Zebra Stripes") {
            model.setZebra(model.document.zebra?.isOn != true)
        }
        .disabled(model.sketch != nil || model.mode == .drawing)
        Divider()
        Button("Model") { model.setMode(.model) }
            .disabled(model.mode == .model)
        // ⌘⇧D toggles, so the item stays enabled in Drawing and takes the person back.
        Button("Drawing") { model.setMode(model.mode == .drawing ? .model : .drawing) }
            .keyboardShortcut("d", modifiers: [.primary, .shift])
    }

    /// The File menu's drawing exports, disabled outside Drawing (plan R25, DR-5 R15).
    static let drawingExportTitles = [
        "Export PDF of All Sheets…", "Export PDF of Sheet…", "Export DXF of Sheet…", "Export DXF of View at 1:1…",
        "Export DXF of View at 1:1 with Annotations…", "Export SVG of Sheet…",
    ]

    /// The drawing exports in menu order.
    static let drawingExportKinds: [DrawingExportKind] = [.pdf, .pdfSheet, .dxfSheet, .dxfView, .dxfViewWithAnnotations, .svgSheet]

    @MainActor
    @MenuContentBuilder
    static func drawingExportItems(_ model: AppModel) -> MenuItems {
        Button(drawingExportTitles[0]) { model.withFilePicker { await model.exportDrawing(drawingExportKinds[0], using: $0) } }
            .disabled(model.mode != .drawing)
        Button(drawingExportTitles[1]) { model.withFilePicker { await model.exportDrawing(drawingExportKinds[1], using: $0) } }
            .disabled(model.mode != .drawing)
        Button(drawingExportTitles[2]) { model.withFilePicker { await model.exportDrawing(drawingExportKinds[2], using: $0) } }
            .disabled(model.mode != .drawing)
        Button(drawingExportTitles[3]) { model.withFilePicker { await model.exportDrawing(drawingExportKinds[3], using: $0) } }
            .disabled(model.mode != .drawing)
        Button(drawingExportTitles[4]) { model.withFilePicker { await model.exportDrawing(drawingExportKinds[4], using: $0) } }
            .disabled(model.mode != .drawing)
        Button(drawingExportTitles[5]) { model.withFilePicker { await model.exportDrawing(drawingExportKinds[5], using: $0) } }
            .disabled(model.mode != .drawing)
    }

    /// File ▸ Import Mesh… and Import KiCad Board….
    @MainActor
    @MenuContentBuilder
    static func importItems(_ model: AppModel) -> MenuItems {
        Button("Import Mesh…") { model.withFilePicker { await model.importMesh(using: $0) } }
            .disabled(!model.canImportMesh)
        Button("Import Model…") { model.withFilePicker { await model.importModel(using: $0) } }
            .disabled(!model.canImportModel)
        Button("Import KiCad Board…") { model.withFilePicker { await model.importKiCadBoard(using: $0) } }
            .disabled(!model.canImportKiCadBoard)
    }

    /// The AI connections switch (MCP-1): a checkmark while on. When another window serves the socket, or the listener couldn't
    /// start, the title says so and choosing the item asks again (`MCPService.menuChosen`).
    @MainActor
    @MenuContentBuilder
    static func aiConnectionsItem(_ model: AppModel) -> MenuItems {
        if let service = model.mcp {
            Toggle(service.menuTitle, isOn: Binding(get: { service.isOn && !service.retries }, set: { service.menuChosen($0) }))
            if service.offersTurnOff { Button(MCPService.turnOffTitle) { service.turnOff() } }
        }
    }
}
