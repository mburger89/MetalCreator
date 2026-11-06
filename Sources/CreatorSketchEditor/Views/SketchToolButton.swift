import MetalUI

/// One tool in the toolbar, marked while it's the active one; its key is in `SketchToolbarKeys` (sketcher spec §8).
struct SketchToolButton: Component {
    let model: SketchEditorModel
    let tool: SketchTool

    var content: some ElementGroup {
        let title = model.tool == tool ? "\(tool.title) ✓" : tool.title
        // No shortcut here: the key is an invisible button in `SketchToolbarKeys`, which fires whichever row is chosen.
        if let key = tool.key {
            Button(title) { model.press(tool) }
                .help("\(tool.title) (\(String(key.character).uppercased()))")
        } else {
            Button(title) { model.press(tool) }
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
        case .spline: "s"
        case .dimension: "d"
        case .trim: "t"
        case .project: "p"
        case .select, .point, .arcThreePoint, .extend, .fillet, .mirror, .pattern: nil
        }
    }
}
