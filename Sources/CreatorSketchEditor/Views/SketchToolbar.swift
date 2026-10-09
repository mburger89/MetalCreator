import CreatorStyle
import MetalUI

/// The sketch toolbar (sketcher spec §8), one row for the top bar: the tools with their keys, Construction (X),
/// Delete (⌫, and ⌦ through `ForwardDeleteKey`) and Finish (⏎), plus Esc. The constraint buttons are in the inspector
/// (`SketchInspector`). Keys are button shortcuts, so a focused field still types them, and they run before the graph
/// panel's keys (MetalUI's key order: a focused field, then button shortcuts, then the window's `onInput`).
public struct SketchToolbar: Component {
    let model: SketchEditorModel
    @Environment(ThemeStore.self) var themes: ThemeStore?

    public init(model: SketchEditorModel) {
        self.model = model
    }

    public var content: some ElementGroup {
        HStack(spacing: Pixels(6)) {
            Text("Sketch").font(.headline).foregroundStyle(SketchColors(themes).primary)
            ForEach(SketchTool.allCases, id: \.self) { tool in
                SketchToolButton(model: model, tool: tool)
            }
            Button(model.isConstruction ? "Construction ✓" : "Construction") { model.toggleConstruction() }
                .keyboardShortcut("x", modifiers: [])
                .help("Construction geometry (X): new geometry, or the selection")
            // Never disabled: a disabled button's shortcut falls through to the graph panel's Delete, which deletes nodes.
            Button("Delete") { model.deleteSelection() }
                .keyboardShortcut(.delete, modifiers: [])
            ForwardDeleteKey(model: model)
            Spacer()
            Button("Finish") { model.finish() }
                .keyboardShortcut(.return, modifiers: [])
            EscapeKey(model: model)
        }
    }
}
