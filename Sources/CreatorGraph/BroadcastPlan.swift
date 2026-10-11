/// How many times a node runs and what each iteration sees (spec §4.2 broadcasting; trees: 7a spec §2).
public struct BroadcastPlan: Sendable {
    public let iterations: Int
    /// True when every item-access input is a single item, so outputs stay `.one`.
    public let isSingle: Bool
    /// Said once on the node when trees were matched whose nesting doesn't line up (`BroadcastPlan+Trees`).
    public let warning: String?
    /// Set instead of running when the trees would make the node run more than `maximumTreeIterations` times.
    public let refusal: String?
    private let itemInputs: [SocketName: Value]
    private let listInputs: [SocketName: [Scalar]]
    private let treeInputs: [SocketName: DataTree]
    /// Present when a tree meets an item or list socket: one entry per iteration, in the order they run.
    let nested: NestedIterations?

    /// True when a tree met an item or list socket, so the node runs once per branch.
    public var isTreeRun: Bool { nested != nil }

    init(iterations: Int, isSingle: Bool, itemInputs: [SocketName: Value], listInputs: [SocketName: [Scalar]],
         treeInputs: [SocketName: DataTree], nested: NestedIterations? = nil, warning: String? = nil,
         refusal: String? = nil) {
        self.iterations = iterations
        self.isSingle = isSingle
        self.itemInputs = itemInputs
        self.listInputs = listInputs
        self.treeInputs = treeInputs
        self.nested = nested
        self.warning = warning
        self.refusal = refusal
    }

    /// Item sockets broadcast over the longest list, and a shorter list repeats its last item.
    /// Any empty list means zero iterations. List sockets always get the whole list. A tree on an item or list
    /// socket broadcasts level by level instead (`BroadcastPlan.nestedPlan`); flat inputs never take that path.
    public static func make(inputs: [SocketName: Value], specs: [SocketSpec]) -> BroadcastPlan {
        let meetsTree = specs.contains { spec in
            if spec.access != .tree, case .tree? = inputs[spec.name] { true } else { false }
        }
        if meetsTree { return nestedPlan(inputs: inputs, specs: specs) }
        var itemInputs: [SocketName: Value] = [:]
        var listInputs: [SocketName: [Scalar]] = [:]
        var treeInputs: [SocketName: DataTree] = [:]
        var counts: [Int] = []
        for spec in specs {
            guard let value = inputs[spec.name] else { continue }
            switch spec.access {
            case .list:
                listInputs[spec.name] = value.items
            case .tree:
                treeInputs[spec.name] = value.asTree ?? .list(value.items)
            case .item:
                itemInputs[spec.name] = value
                if case .list(let scalars) = value { counts.append(scalars.count) }
            }
        }
        guard let longest = counts.max() else {
            return BroadcastPlan(iterations: 1, isSingle: true, itemInputs: itemInputs, listInputs: listInputs,
                                 treeInputs: treeInputs)
        }
        let iterations = counts.contains(0) ? 0 : longest
        return BroadcastPlan(iterations: iterations, isSingle: false, itemInputs: itemInputs, listInputs: listInputs,
                             treeInputs: treeInputs)
    }

    public func inputs(at item: Int) -> NodeInputs {
        if let nested { return NodeInputs(item: item, slots: nested.slots[item]) }
        var slots: [SocketName: NodeInputs.Slot] = [:]
        for (name, value) in itemInputs {
            switch value {
            case .one(let scalar): slots[name] = .item(scalar)
            case .list(let scalars): slots[name] = .item(scalars[min(item, scalars.count - 1)])
            case .tree: break  // A tree on an item socket takes the nested plan, never this one.
            }
        }
        for (name, scalars) in listInputs {
            slots[name] = .list(scalars)
        }
        for (name, tree) in treeInputs {
            slots[name] = .tree(tree)
        }
        return NodeInputs(item: item, slots: slots)
    }

    /// One output's value from what each iteration produced (`results[i]` is iteration `i`'s items). A flat plan
    /// joins them into one list, which is a single item only for a single run that made one item by itself
    /// (`producedList` false); a nested plan puts them back in the nesting of the inputs, one level per level matched.
    public func assemble(_ results: [[Scalar]], producedList: Bool) -> Value {
        if let nested { return Value(nested.tree(of: results)) }
        let scalars = results.flatMap { $0 }
        if isSingle, !producedList, scalars.count == 1, let only = scalars.first { return .one(only) }
        return .list(scalars)
    }
}
