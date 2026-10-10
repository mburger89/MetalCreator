import MetalUI

/// One tool in the toolbar, marked while it's the active one, with its key (sketcher spec §8).
struct SketchToolButton: Component {
    let model: SketchEditorModel
    let tool: SketchTool

    var content: some ElementGroup {
        let title = model.tool == tool ? "\(tool.title) ✓" : tool.title
        if let key = tool.key {
            Button(title) { model.choose(tool) }
                .keyboardShortcut(key, modifiers: [])
                .help("\(tool.title) (\(String(key.character).uppercased()))")
        } else {
            Button(title) { model.choose(tool) }
        }
    }
}

extension SketchTool {
    /// The tool's key (sketcher spec §8's table), or `nil` for none.
    var key: KeyEquivalent? {
        switch self {
        case .line: "l"
        case .arc: "a"
        case .circle: "c"
        case .dimension: "d"
        case .trim: "t"
        case .select, .point, .extend, .fillet, .mirror, .pattern: nil
        }
    }
}
