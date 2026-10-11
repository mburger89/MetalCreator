extension BroadcastPlan {
    /// The most times a tree broadcast may run a node, so two lopsided trees can't hang the app.
    public static let maximumTreeIterations = 100_000

    /// Broadcasting level by level (7a spec §2), used when a tree meets an item or list socket. Inputs match on their
    /// outermost level first, then the next; at each level a shorter side repeats its last branch, and an empty one
    /// means no branches. A single item or a flat list applies to every branch of a deeper tree (a flat list then
    /// matches the items of each branch, as flat lists always did). A list socket takes one branch per run, so it
    /// uses up one level of its tree. Trees of different depth that both nest (3 × 8 against 2 × 3 × 4) are matched
    /// from the outermost level and the node says so once, naming both shapes. Outputs keep the deepest nesting.
    static func nestedPlan(inputs: [SocketName: Value], specs: [SocketSpec]) -> BroadcastPlan {
        var cursors: [TreeCursor] = []
        var treeInputs: [SocketName: DataTree] = [:]
        for spec in specs {
            guard let value = inputs[spec.name] else { continue }
            if spec.access == .tree {
                treeInputs[spec.name] = value.asTree ?? .list(value.items)
            } else {
                cursors.append(TreeCursor(name: spec.name, access: spec.access, state: TreeCursor.State(value)))
            }
        }
        let depth = cursors.map(\.remaining).max() ?? 0
        var expansion = Expansion(treeInputs: treeInputs)
        let layout = expansion.expand(cursors)
        guard !expansion.overflowed else {
            let shapes = cursors.filter { $0.remaining > 0 }.sorted { $0.name < $1.name }.compactMap { cursor in
                inputs[cursor.name].map { "“\(cursor.name)” is \($0.shapeText)" }
            }
            let refusal = "These trees would run the node more than \(maximumTreeIterations.shapeNumber) times. "
                + "Check their shapes: \(shapes.joined(separator: ", "))."
            return BroadcastPlan(iterations: 0, isSingle: false, itemInputs: [:], listInputs: [:], treeInputs: [:],
                                 refusal: refusal)
        }
        let nested = NestedIterations(depth: depth, layout: layout, slots: expansion.slots)
        return BroadcastPlan(iterations: expansion.slots.count, isSingle: false, itemInputs: [:], listInputs: [:],
                             treeInputs: [:], nested: nested, warning: mismatchWarning(cursors, inputs: inputs))
    }

    /// "“a” (3 × 8) and “b” (2 × 3 × 4) nest differently, …" when the inputs that are trees of depth 2 or more are
    /// not all the same depth; `nil` when they agree. (A list socket uses up one level of its tree, so depth, not the
    /// levels left, is what is compared.)
    private static func mismatchWarning(_ cursors: [TreeCursor], inputs: [SocketName: Value]) -> String? {
        let structured = cursors.filter(\.isStructured).sorted { $0.name < $1.name }
        guard let shallow = structured.min(by: { $0.treeDepth < $1.treeDepth }),
              let deep = structured.max(by: { $0.treeDepth < $1.treeDepth }),
              shallow.treeDepth != deep.treeDepth,
              let shallowValue = inputs[shallow.name], let deepValue = inputs[deep.name] else { return nil }
        return "“\(shallow.name)” (\(shallowValue.shapeText)) and “\(deep.name)” (\(deepValue.shapeText)) "
            + "nest differently, so they were matched from the outermost level."
    }

    /// Walks the inputs down, level by level, collecting the slots of every run.
    private struct Expansion {
        var slots: [[SocketName: NodeInputs.Slot]] = []
        var overflowed = false
        let treeInputs: [SocketName: DataTree]

        mutating func expand(_ cursors: [TreeCursor]) -> NestedIterations.Layout {
            let deepest = cursors.map(\.remaining).max() ?? 0
            if deepest == 0 {
                guard slots.count < BroadcastPlan.maximumTreeIterations else {
                    overflowed = true
                    return .branches([])
                }
                var slot: [SocketName: NodeInputs.Slot] = treeInputs.mapValues { .tree($0) }
                for cursor in cursors { slot[cursor.name] = cursor.slot }
                slots.append(slot)
                return .leaf(slots.count - 1)
            }
            let stepping = cursors.map { $0.steps(whenDeepest: deepest) }
            let counts = zip(cursors, stepping).filter(\.1).map(\.0.count)
            let branchCount = counts.contains(0) ? 0 : counts.max() ?? 0
            var children: [NestedIterations.Layout] = []
            for index in 0..<branchCount where !overflowed {
                let next = zip(cursors, stepping).map { $1 ? $0.stepped(to: index) : $0 }
                children.append(expand(next))
            }
            return .branches(children)
        }
    }
}
