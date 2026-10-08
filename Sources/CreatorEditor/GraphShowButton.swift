import MetalUI

/// The hidden graph panel's way back (spec §6.1, "Hidden (⇥ toggles it)"). The shell shows it
/// while `EditorModel.isPanelVisible` is false. Its Tab shortcut is claimed in MetalUI's button
/// shortcut stage, which runs before focus traversal would take Tab (gap M5-b).
public struct GraphShowButton: Component {
    public let model: EditorModel

    public init(model: EditorModel) {
        self.model = model
    }

    public var content: some ElementGroup {
        GlassPanel {
            Button("Show graph") { model.toggleHidden() }
                .keyboardShortcut(.tab, modifiers: [])
                .help("Show the graph (Tab)")
        }
    }
}
