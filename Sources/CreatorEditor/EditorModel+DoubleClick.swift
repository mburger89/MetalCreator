import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Double-clicking (sketcher spec §8: "Enter by double-clicking a Sketch node"; the groups spec's §6 enters a group the
/// same way; the comments typing plan, spec 2026-10-09 §8, edits a note or a frame's title). The click count is the
/// platform's, from the press's `DragGesture.Value.clickCount` (MetalUI C16, docs/metalui-gaps.md S5-b), so when two
/// clicks make a double click, and how far apart they may land, is the user's System Settings > Mouse setting, not a
/// time of ours. The model adds only what the platform can't know: both clicks have no modifiers and land on the same
/// target, which is a node's body, a note, or a frame's title bar.
extension EditorModel {
    /// The inspector buttons a double click on a node presses; the first of them a node's inspector has wins: a Sketch
    /// node's "Edit sketch", a group node's "Edit Group" (groups spec §6).
    static let doubleClickActions: [InspectorAction] = [.editSketch, .editGroup]

    /// A press released without a drag, on `hit` at `point` with `modifiers` held and the platform's `clickCount`. A
    /// first click (count 1) on a target remembers it; a second (count 2) on the same target is a double click
    /// (`doubleClicked`). A third or later click (count 3 and up) is neither, and a socket, a frame's edge band, empty
    /// canvas or a modifier forgets the first.
    func countClick(on hit: CanvasHit, at point: Vector2, modifiers: CanvasModifiers, clickCount: Int) {
        guard modifiers.isEmpty, let target = clickTarget(for: hit, at: point) else {
            lastClick = nil
            return
        }
        let first = lastClick
        lastClick = clickCount == 1 ? target : nil
        if clickCount == 2, first == target { doubleClicked(target) }
    }

    /// The target a press on `hit` at `point` (canvas-local screen points) can double-click: a node, a note, or a
    /// frame's title bar. A frame's edge band is `.frame` too, for grabbing it, but is no target.
    func clickTarget(for hit: CanvasHit, at point: Vector2) -> ClickTarget? {
        switch hit {
        case .node(let node):
            return .node(node)
        case .note(let id):
            return .note(id)
        case .frame(let id):
            guard let rect = frame(ofComment: id), CommentLayout.titleBar(of: rect).contains(transform.toCanvas(point)) else {
                return nil
            }
            return .frameTitle(id)
        case .socket, .resize, .empty:
            return nil
        }
    }

    private func doubleClicked(_ target: ClickTarget) {
        switch target {
        case .node(let node): nodeDoubleClicked(node)
        case .note(let id), .frameTitle(let id): beginEditing(id)
        }
    }

    /// A double click on `node`: presses what `doubleClickAction(for:)` finds (the Sketch node's "Edit sketch"),
    /// exactly as the button does; a node without one only stays selected.
    public func nodeDoubleClicked(_ node: NodeID) {
        if let action = doubleClickAction(for: node) { press(action, on: node) }
    }

    /// The first of `doubleClickActions` among `node`'s inspector buttons, if any.
    func doubleClickAction(for node: NodeID) -> InspectorAction? {
        guard let typeID = graph.nodes[node]?.typeID, let definition = registry[typeID] else { return nil }
        let buttons = definition.inspector.flatMap(\.controls).compactMap { control -> InspectorAction? in
            if case .button(_, let action) = control { action } else { nil }
        }
        return Self.doubleClickActions.first { buttons.contains($0) }
    }
}
