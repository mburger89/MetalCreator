import MetalUI

/// Esc while sketching (sketcher spec §8): ends the stroke in progress, clears the selection, or finishes. A button
/// shortcut, drawn invisibly (MetalUI fires a hidden button's shortcut), so it runs before the graph panel's Escape.
struct EscapeKey: Component {
    let model: SketchEditorModel

    var content: some ElementGroup {
        Button("Escape") { model.escape() }
            .keyboardShortcut(.escape, modifiers: [])
            .frame(width: Pixels(0), height: Pixels(0))
            .opacity(0)
            .allowsHitTesting(false)
    }
}
