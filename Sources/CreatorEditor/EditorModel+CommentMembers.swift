import CreatorGraph

extension EditorModel {
    /// The items a move of `items` carries: themselves, and the nodes each selected frame holds (canvas comments
    /// spec 2026-10-09 §7), so dragging or nudging a frame moves it and its members as one step. Membership is read
    /// when the move begins and never stored.
    func carried(by items: CanvasSelection) -> CanvasSelection {
        var carried = items
        for id in items.comments {
            if let box = graph.frames[id] { carried.nodes.formUnion(members(of: box)) }
        }
        return carried
    }
}
