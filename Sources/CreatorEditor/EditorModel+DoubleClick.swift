import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Double-clicking (sketcher spec §8: "Enter by double-clicking a Sketch node"; the groups spec's §6 enters a group the
/// same way; the comments typing plan, spec 2026-10-09 §8, edits a note or a frame's title). The canvas's one
/// zero-distance drag reports each click alone, without the click count (docs/metalui-gaps.md S5-b, the double-click
/// half of GI-a), so the model pairs them: a click with no modifiers on the same target within `doubleClickInterval`
/// and `doubleClickSlop` of the one before. A target is a node's body, a note, or a frame's title bar.
extension EditorModel {
    /// The longest gap between a double click's two clicks (the groups spec's 0.4 s, §6).
    public static let doubleClickInterval = Duration.milliseconds(400)
    /// How far apart a double click's two clicks may land, in screen points.
    public static let doubleClickSlop = 4.0
    /// The inspector buttons a double click on a node presses; the first of them a node's inspector has wins: a Sketch
    /// node's "Edit sketch", a group node's "Edit Group" (groups spec §6).
    static let doubleClickActions: [InspectorAction] = [.editSketch, .editGroup]

    /// A press released without a drag, on `hit` at `point` with `modifiers` held: the second click with no modifiers
    /// on one target is a double click (`doubleClicked`); any other click on a target starts a new pair, and a socket,
    /// a frame's edge band, empty canvas or a modifier starts none.
    func pairClick(on hit: CanvasHit, at point: Vector2, modifiers: CanvasModifiers) {
        guard modifiers.isEmpty, let target = clickTarget(for: hit, at: point) else {
            lastClick = nil
            return
        }
        let time = now()
        if let last = lastClick, last.target == target, (point - last.point).length <= Self.doubleClickSlop,
           last.time.duration(to: time) <= Self.doubleClickInterval {
            lastClick = nil
            doubleClicked(target)
        } else {
            lastClick = RecentClick(target: target, point: point, time: time)
        }
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
