/// How many times a node runs and what each iteration sees (spec §4.2 broadcasting).
public struct BroadcastPlan: Sendable {
    public let iterations: Int
    /// True when every item-access input is a single item, so outputs stay `.one`.
    public let isSingle: Bool
    private let itemInputs: [SocketName: Value]
    private let listInputs: [SocketName: [Scalar]]
    private let treeInputs: [SocketName: DataTree]

    /// Item sockets broadcast over the longest list, and a shorter list repeats its last item.
    /// Any empty list means zero iterations. List sockets always get the whole list.
    public static func make(inputs: [SocketName: Value], specs: [SocketSpec]) -> BroadcastPlan {
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
                if case .tree(let tree) = value { counts.append(tree.itemCount) }
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
        var slots: [SocketName: NodeInputs.Slot] = [:]
        for (name, value) in itemInputs {
            switch value {
            case .one(let scalar): slots[name] = .item(scalar)
            case .list(let scalars): slots[name] = .item(scalars[min(item, scalars.count - 1)])
            case .tree(let tree):
                let scalars = tree.items
                slots[name] = .item(scalars[min(item, scalars.count - 1)])
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
}
