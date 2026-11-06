import MetalUI

/// Every key of the sketch toolbar, as invisible buttons that are always present (outside its `ViewThatFits`, whose
/// unchosen rows register no shortcut, and whose "More" menu items only display theirs): a key fires once whichever row
/// is chosen. The visible buttons carry no shortcut of their own.
///
/// Delete is never disabled: a disabled button's shortcut falls through to the graph panel's Delete, which deletes nodes.
struct SketchToolbarKeys: Component {
    let model: SketchEditorModel

    var content: some ElementGroup {
        HStack(spacing: Pixels(0)) {
            ForEach(SketchTool.allCases.filter { $0.key != nil }, id: \.self) { tool in
                if let key = tool.key {
                    Button(tool.title) { model.press(tool) }
                        .keyboardShortcut(key, modifiers: [])
                        .frame(width: Pixels(0), height: Pixels(0))
                }
            }
            Button("Construction") { model.toggleConstruction() }
                .keyboardShortcut("x", modifiers: [])
                .frame(width: Pixels(0), height: Pixels(0))
            Button("Delete") { model.deleteSelection() }
                .keyboardShortcut(.delete, modifiers: [])
                .frame(width: Pixels(0), height: Pixels(0))
            Button("Finish") { model.finish() }
                .keyboardShortcut(.return, modifiers: [])
                .frame(width: Pixels(0), height: Pixels(0))
            ForwardDeleteKey(model: model)
            EscapeKey(model: model)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
