import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Double-clicking a node (sketcher spec §8: "Enter by double-clicking a Sketch node"; the groups spec's §6 enters a
/// group the same way). The canvas's one zero-distance drag reports each click alone, without the click count
/// (docs/metalui-gaps.md S5-b, the double-click half of GI-a), so the model pairs them: a click with no modifiers on
/// the same node's body within `doubleClickInterval` and `doubleClickSlop` of the one before.
extension EditorModel {
    /// The longest gap between a double click's two clicks (the groups spec's 0.4 s, §6).
    public static let doubleClickInterval = Duration.milliseconds(400)
    /// How far apart a double click's two clicks may land, in screen points.
    public static let doubleClickSlop = 4.0
    /// The inspector buttons a double click presses; the first of them a node's inspector has wins: a Sketch node's
    /// "Edit sketch", a group node's "Edit Group" (groups spec §6).
    static let doubleClickActions: [InspectorAction] = [.editSketch, .editGroup]

    /// A press released without a drag, on `hit` at `point` with `modifiers` held: the second click with no modifiers
    /// on one node's body is a double click (`nodeDoubleClicked`); any other click on a body starts a new pair, and a
    /// socket, empty canvas or a modifier starts none.
    func pairClick(on hit: CanvasHit, at point: Vector2, modifiers: CanvasModifiers) {
        guard case .node(let node) = hit, modifiers.isEmpty else {
            lastNodeClick = nil
            return
        }
        let time = now()
        if let last = lastNodeClick, last.node == node, (point - last.point).length <= Self.doubleClickSlop,
           last.time.duration(to: time) <= Self.doubleClickInterval {
            lastNodeClick = nil
            nodeDoubleClicked(node)
        } else {
            lastNodeClick = NodeClick(node: node, point: point, time: time)
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
