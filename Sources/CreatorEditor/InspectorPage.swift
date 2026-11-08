/// Everything the context inspector shows: the selected node's header and sections (when
/// exactly one node is selected), then the document parameters, which are always listed.
public struct InspectorPage: Equatable, Sendable {
    public var header: InspectorHeader?
    public var sections: [InspectorSectionRows]
    public var parameters: [ParameterRow]
    /// The selected comments' page: set when comments are selected and no node is (`EditorModel.inspectorPage`).
    public var comment: CommentPage?
    /// The definition behind the selected group node, Group Input or Group Output (`EditorModel.groupPanel`).
    public var group: GroupPanel?
}

extension InspectorPage {
    /// About how tall the page draws, in points: enough to tell a page the window may not hold from one it surely does (the
    /// inspector scrolls only the first; `InspectorPanel`). Rows are one line each except an opened path list, which adds a line per
    /// branch, a note under a label and a comment's or group's page, which are counted by their parts; it is an estimate, never a layout.
    public var estimatedHeight: Double {
        let line = 30.0, title = 28.0, gap = 10.0
        var height = header == nil ? 0 : 40 + gap
        for section in sections {
            height += title + gap
            for row in section.rows {
                switch row {
                case .treeShape(let shape):
                    height += 2 * line
                    if shape.isExpanded { height += Double(shape.entries.count + (shape.hiddenCount > 0 ? 1 : 0)) * 20 }
                case .recipe: height += 2 * line
                case .anchorGrid: height += 110
                case .segmented, .planePicker, .vector: height += 1.5 * line
                default: height += line
                }
            }
        }
        if comment != nil { height += 300 }
        if let group { height += title + gap + Double(group.sockets.count + 4) * line }
        return height + title + gap + Double(max(parameters.count, 1)) * line
    }
}
