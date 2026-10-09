import MetalUI

/// Forward delete (⌦, fn-⌫) while sketching: deletes the selection, as ⌫ does. The graph panel maps both keys to
/// deleting nodes, and while sketching the graph's selection is the Sketch node being edited, so without this a
/// forward delete would delete it. A button shortcut drawn invisibly, as `EscapeKey` is, so it runs before the graph
/// panel's keys; never disabled, so the key never falls through.
struct ForwardDeleteKey: Component {
    let model: SketchEditorModel

    var content: some ElementGroup {
        Button("Delete Forward") { model.deleteSelection() }
            .keyboardShortcut(.deleteForward, modifiers: [])
            .frame(width: Pixels(0), height: Pixels(0))
            .opacity(0)
            .allowsHitTesting(false)
    }
}
