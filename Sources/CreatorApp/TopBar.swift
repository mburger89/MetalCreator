import CreatorDrawingEditor
import CreatorEditor
import CreatorKernel
import CreatorSketchEditor
import CreatorStyle
import MetalUI

/// The glass top bar (spec §6.1): the document's name, the Preview menu, the Analysis menu (checkable Section, Measure and Zebra,
/// which can be on together), Undo and Redo (icon buttons, each titled by its step, `AppModel.undoTitle`, in its tooltip and accessibility label) and Export (an icon menu). While a sketch is open it holds the sketch toolbar instead (sketcher spec §8:
/// "Toolbar (glass, top)"), in chrome opaque to the pointer. The name and the gap beside the controls are window drag
/// handles (gap M6-c, `WindowDragHandle`): the window has no title bar to drag it by.
struct TopBar: Component {
    let model: AppModel
    @Environment(ThemeStore.self) var themes: ThemeStore?
    /// How far the content starts in so that it clears the window buttons under a hidden title bar (gap M6-c): the
    /// window root passes `AppLayout.topBarClearance` of the window's `titleBarInsets`; zero in a standard window.
    var clearance = Pixels(0)
    /// The same at the trailing end, for the buttons MetalUI draws at the window's right on Linux and Windows (MetalUI S1,
    /// `AppLayout.topBarTrailingClearance`); zero on macOS.
    var trailingClearance = Pixels(0)

    var content: some ElementGroup {
        let clearButtons = Edges(top: Pixels(0), right: trailingClearance, bottom: Pixels(0), left: clearance)
        if let sketch = model.sketch {
            SketchChrome(.topBar) { ZStack(alignment: .topLeading) { SketchToolbar(model: sketch.editor) }.padding(clearButtons) }
        } else {
            GlassPanel(.topBar, takesPointer: false) {
                HStack(spacing: Pixels(10)) {
                    Text(model.isEdited ? "\(model.displayName) — Edited" : model.displayName)
                        .font(.headline)
                        .foregroundStyle(Palette(themes).primaryText.color)
                        .lineLimit(1)
                        .background { WindowDragHandle() }
                    WindowDragHandle()
                    // The mode switch is in both modes (plan R21); the sketch's own bar has none.
                    Picker("Workspace", selection: Binding(get: { model.mode }, set: { model.setMode($0) })) {
                        ForEach(WorkspaceMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if model.mode == .drawing {
                        // The Preview picker and the Analysis menu act on the viewport, so Drawing has neither (plan R28).
                        DrawingToolbar(model: model.drawing.editor)
                    } else {
                        Picker("Preview", selection: Binding(get: { model.previewMode }, set: { model.previewMode = $0 })) {
                            ForEach(PreviewMode.allCases, id: \.self) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .layoutPriority(2)
                        Menu("Analysis") {
                            Toggle("Section", isOn: Binding(get: { model.document.section?.isOn == true }, set: { model.setSection($0) }))
                            Toggle("Measure", isOn: Binding(get: { model.measure != nil }, set: { model.setMeasure($0) }))
                                .disabled(model.pick != nil)
                            Toggle("Zebra", isOn: Binding(get: { model.document.zebra?.isOn == true }, set: { model.setZebra($0) }))
                        }
                    }
                    // Only a control that can be disabled needs the backdrop: an enabled one registers its own hitbox, a disabled
                    // one none, so a press on it would orbit the viewport under the bar's padding.
                    // Icons, one borderless style: the step's title is the tooltip and the accessibility label (the bundled
                    // glyphs carry none of their own).
                    Button { model.undo() } label: { ToolbarIcon.image("arrow.uturn.backward") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(model.undoTitle)
                        .help(model.undoTitle)
                        .disabled(!model.document.canUndo)
                        .absorbsPointer()
                    Button { model.redo() } label: { ToolbarIcon.image("arrow.uturn.forward") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(model.redoTitle)
                        .help(model.redoTitle)
                        .disabled(!model.document.canRedo)
                        .absorbsPointer()
                    Menu(content: {
                        Button("STEP…") { model.withFilePicker { await model.exportDocument(.step, using: $0) } }
                        Button("STL…") { model.withFilePicker { await model.exportDocument(.stl, using: $0) } }
                        if model.mode == .drawing {
                            Button("PDF of All Sheets…") { model.withFilePicker { await model.exportDrawing(.pdf, using: $0) } }
                            Button("PDF of Sheet…") { model.withFilePicker { await model.exportDrawing(.pdfSheet, using: $0) } }
                            Button("DXF of Sheet…") { model.withFilePicker { await model.exportDrawing(.dxfSheet, using: $0) } }
                            Button("DXF of View at 1:1…") { model.withFilePicker { await model.exportDrawing(.dxfView, using: $0) } }
                            Button("DXF of View at 1:1 with Annotations…") {
                                model.withFilePicker { await model.exportDrawing(.dxfViewWithAnnotations, using: $0) }
                            }
                            Button("SVG of Sheet…") { model.withFilePicker { await model.exportDrawing(.svgSheet, using: $0) } }
                        }
                    }, label: { ToolbarIcon.image("square.and.arrow.up") })
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Export")
                    .help("Export")
                }
                .padding(clearButtons)
            }
        }
    }
}
