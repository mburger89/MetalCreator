import CreatorStyle
import MetalUI

/// The drawing toolbar, one row for the top bar: the twenty-one tools (Base View to Revision Table: Assembly View after Projected
/// View, Balloon, Parts List and Revision Table after Surface Finish; a check while chosen), then the drag gap. It is a
/// `ViewThatFits` over `candidateCount` rows, as the sketch toolbar is: row k shows all but the last k tools as buttons and puts
/// those k in a "More" menu, so tools leave the row from the end as the window narrows, and the first row that fits wins. The gap
/// has the lowest layout priority, so the buttons are sized first and it takes what is left; it is a window drag handle, since
/// the window is dragged by the bar's empty parts.
public struct DrawingToolbar: Component {
    let model: DrawingEditorModel

    public init(model: DrawingEditorModel) {
        self.model = model
    }

    /// The tools that have a button, in order.
    static var tools: [DrawingTool] { DrawingTool.allCases.filter { $0.title != nil } }

    /// One row for each number of tools in More, 0 (none) to all of them.
    static var candidateCount: Int { tools.count + 1 }

    public var content: some ElementGroup {
        ViewThatFits(in: .horizontal) {
            ForEach(0..<Self.candidateCount, id: \.self) { inMore in
                DrawingToolbarRow(model: model, inMore: inMore)
            }
        }
    }
}

/// One candidate row of the toolbar.
struct DrawingToolbarRow: Component {
    let model: DrawingEditorModel
    let inMore: Int

    var content: some ElementGroup {
        let tools = DrawingToolbar.tools
        let shown = Array(tools.dropLast(inMore))
        let hidden = Array(tools.suffix(inMore))
        HStack(spacing: Pixels(3)) {
            ForEach(shown, id: \.self) { tool in
                Button(Self.label(of: tool, in: model)) { model.press(tool) }
            }
            if !hidden.isEmpty {
                // A String variable, never a literal: a title built from data is not Markdown.
                let title = hidden.contains(model.tool) ? "More ✓" : "More"
                Menu(title) {
                    for tool in hidden {
                        Button(Self.label(of: tool, in: model)) { model.press(tool) }
                    }
                }
            }
            // A greedy handle in a stack is offered a share before the buttons are sized, which would cut their labels.
            WindowDragHandle().layoutPriority(-1)
        }
    }

    static func label(of tool: DrawingTool, in model: DrawingEditorModel) -> String {
        let title = tool.title ?? ""
        return model.tool == tool ? "\(title) ✓" : title
    }
}
