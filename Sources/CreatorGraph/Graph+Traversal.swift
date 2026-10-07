import CreatorKernel

extension Graph {
    public func incomingLink(to endpoint: Endpoint) -> Link? {
        links.first { $0.to == endpoint }
    }

    /// Every node that `demand` depends on, upstream first, deterministic. Cycles (possible
    /// only in hand-edited files) are reported in `cyclic` instead of looping.
    ///
    /// `order` includes cyclic nodes; callers must treat nodes in `cyclic` as errors. Nodes
    /// downstream of a cycle are not in `cyclic` — they simply have no upstream result.
    public func evaluationOrder(for demand: Set<NodeID>) -> EvaluationOrder {
        var visited: Set<NodeID> = []
        var order: [NodeID] = []

        func sources(of id: NodeID) -> [NodeID] {
            links.filter { $0.to.node == id }.map(\.from.node).sorted()
        }

        func visit(_ id: NodeID) {
            guard nodes[id] != nil, visited.insert(id).inserted else { return }
            for source in sources(of: id) { visit(source) }
            order.append(id)
        }

        for id in demand.sorted() { visit(id) }
        return EvaluationOrder(order: order, cyclic: cyclicNodes(among: order))
    }

    /// Exact cycle membership via Tarjan's strongly connected components over `ids` (which
    /// must be closed under "reads from"): every node in a component of size > 1, plus
    /// any node wired to itself.
    private func cyclicNodes(among ids: [NodeID]) -> Set<NodeID> {
        var index = 0
        var indices: [NodeID: Int] = [:]
        var lowLinks: [NodeID: Int] = [:]
        var onStack: Set<NodeID> = []
        var stack: [NodeID] = []
        var cyclic: Set<NodeID> = []

        func connect(_ id: NodeID) {
            indices[id] = index
            lowLinks[id] = index
            index += 1
            stack.append(id)
            onStack.insert(id)
            let sources = links.filter { $0.to.node == id }.map(\.from.node).sorted()
            for source in sources where nodes[source] != nil {
                if source == id { cyclic.insert(id) }
                if indices[source] == nil {
                    connect(source)
                    lowLinks[id] = min(lowLinks[id] ?? 0, lowLinks[source] ?? 0)
                } else if onStack.contains(source) {
                    lowLinks[id] = min(lowLinks[id] ?? 0, indices[source] ?? 0)
                }
            }
            if lowLinks[id] == indices[id] {
                var component: [NodeID] = []
                while let top = stack.popLast() {
                    onStack.remove(top)
                    component.append(top)
                    if top == id { break }
                }
                if component.count > 1 { cyclic.formUnion(component) }
            }
        }

        for id in ids where indices[id] == nil { connect(id) }
        return cyclic
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
