import CreatorStyle
import MetalUI

/// The sketch toolbar (sketcher spec §8), one row for the top bar: the tools, Construction (X), Delete (⌫, and ⌦
/// through `ForwardDeleteKey`) and Finish (⏎), plus Esc. The constraint buttons are in the inspector (`SketchInspector`).
///
/// The row is a `ViewThatFits` over `SketchToolbar.candidateCount` rows (gap TB-a): row k shows the first `tools.count - k`
/// tools as buttons and puts the last k in a "More" menu, so tools leave the row from the end as the window narrows.
/// Construction, Delete, the drag gap and Finish are in every row. The first row that fits wins, the last is the fallback.
///
/// Keys are button shortcuts, so a focused field still types them, and they run before the graph panel's keys (MetalUI's
/// key order: a focused field, then button shortcuts, then the window's `onInput`). A candidate that is not chosen
/// registers no shortcut, and a closed `Menu` item's is display only (MetalUI ruling MN-D), so every key is an invisible
/// button in `SketchToolbarKeys`, outside the `ViewThatFits`, always present; the visible buttons and menu items register
/// none. The label and the gap before Finish are window drag handles (gap M6-c): the window is dragged by the empty parts
/// of the bar. The gap has the lowest layout priority, so the buttons are sized first and it takes what is left.
public struct SketchToolbar: Component {
    let model: SketchEditorModel
    @Environment(ThemeStore.self) var themes: ThemeStore?

    public init(model: SketchEditorModel) {
        self.model = model
    }

    /// One row for each number of tools in More, 0 (none) to all of them.
    static var candidateCount: Int { SketchTool.allCases.count + 1 }

    public var content: some ElementGroup {
        HStack(spacing: Pixels(3)) {
            Text("Sketch").font(.headline).foregroundStyle(SketchColors(themes).primary)
                .background { WindowDragHandle() }
            ViewThatFits(in: .horizontal) {
                ForEach(0..<Self.candidateCount, id: \.self) { inMore in
                    SketchToolbarRow(model: model, inMore: inMore)
                }
            }
        }
        // Outside the stack's slots, so the rows get all the width but the label's.
        .background { SketchToolbarKeys(model: model) }
    }
}

/// One candidate row of the toolbar: all but the last `inMore` tools as buttons, those in a "More" menu.
struct SketchToolbarRow: Component {
    let model: SketchEditorModel
    let inMore: Int

    var content: some ElementGroup {
        let tools = SketchTool.allCases
        let shown = Array(tools.dropLast(inMore))
        let hidden = Array(tools.suffix(inMore))
        HStack(spacing: Pixels(3)) {
            ForEach(shown, id: \.self) { tool in
                SketchToolButton(model: model, tool: tool)
            }
            if !hidden.isEmpty {
                // A String variable, never a literal: a title built from data is not Markdown.
                let title = hidden.contains(model.tool) ? "More ✓" : "More"
                Menu(title) {
                    for tool in hidden {
                        Button(model.tool == tool ? "\(tool.title) ✓" : tool.title) { model.press(tool) }
                    }
                }
            }
            Button(model.isConstruction ? "Construction ✓" : "Construction") { model.toggleConstruction() }
                .help("Construction geometry (X): new geometry, or the selection")
            Button("Delete") { model.deleteSelection() }
            // A greedy handle in a stack is offered a share before the buttons are sized, which would cut their labels.
            WindowDragHandle().layoutPriority(-1)
            Button("Finish") { model.finish() }
        }
    }
}
