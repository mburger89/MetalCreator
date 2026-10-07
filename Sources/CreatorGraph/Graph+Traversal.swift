import CreatorKernel

extension Graph {
    public func incomingLink(to endpoint: Endpoint) -> Link? {
        links.first { $0.to == endpoint }
    }

    /// Every node that `demand` depends on, upstream first, deterministic. Cycles (possible
    /// only in hand-edited files) are reported in `cyclic` instead of looping.
    public func evaluationOrder(for demand: Set<NodeID>) -> EvaluationOrder {
        enum Mark { case visiting, done }
        var marks: [NodeID: Mark] = [:]
        var order: [NodeID] = []
        var cyclic: Set<NodeID> = []
        var stack: [NodeID] = []

        func visit(_ id: NodeID) {
            switch marks[id] {
            case .done?:
                return
            case .visiting?:
                if let start = stack.lastIndex(of: id) { cyclic.formUnion(stack[start...]) }
                return
            case nil:
                break
            }
            guard nodes[id] != nil else { return }
            marks[id] = .visiting
            stack.append(id)
            let sources = links.filter { $0.to.node == id }.map(\.from.node).sorted()
            for source in sources { visit(source) }
            stack.removeLast()
            marks[id] = .done
            order.append(id)
        }

        for id in demand.sorted() { visit(id) }
        return EvaluationOrder(order: order, cyclic: cyclic)
    }

    /// `id` and everything it reads from, directly or indirectly.
    public func upstreamClosure(of id: NodeID) -> Set<NodeID> {
        var seen: Set<NodeID> = []
        var pending = [id]
        while let next = pending.popLast() {
            guard seen.insert(next).inserted else { continue }
            pending += links.filter { $0.to.node == next }.map(\.from.node)
        }
        return seen
    }

    /// `ids` and everything that reads from them, directly or indirectly.
    public func downstreamClosure(of ids: Set<NodeID>) -> Set<NodeID> {
        var seen: Set<NodeID> = []
        var pending = Array(ids)
        while let next = pending.popLast() {
            guard seen.insert(next).inserted else { continue }
            pending += links.filter { $0.from.node == next }.map(\.to.node)
        }
        return seen
    }
}
