import CreatorKernel

extension Evaluator {
    /// A group node's result, the key its consumers' keys build on, and whether anything inside it ran.
    struct GroupOutcome {
        var result: NodeResult
        var key: CacheKey
        var ran: Bool
    }

    /// Runs group node `node` (groups spec §5): its definition's graph, demanding Group Output, with Group Input
    /// handing on `inputs` unchanged (no broadcasting here; nodes inside broadcast as usual). The group node takes
    /// Group Output's inputs as its outputs. It isn't cached itself: its inner nodes are, each under its own scoped
    /// identity, so instances never share entries and a definition edit misses exactly the nodes it changed. Its key
    /// joins its own gathered key with Group Output's, so consumers re-run when the inside changes.
    func evaluateGroup(_ node: Node, inputs: [SocketName: Value], key: CacheKey, scope: EvaluationScope,
                       trace: inout EvaluationTrace) async throws -> GroupOutcome {
        func failure(_ message: String) -> GroupOutcome {
            GroupOutcome(result: NodeResult(state: .error(message)), key: key, ran: false)
        }
        guard let definition = scope.setup.registry.group(of: node) else { return failure("This group's definition is missing.") }
        guard !scope.groups.contains(definition.id) else {
            return failure("“\(definition.name)” contains itself, so it can't be evaluated.")
        }
        guard definition.inputNode != nil, let output = definition.outputNode else {
            return failure("“\(definition.name)” has no Group Input or Group Output.")
        }
        let clock = ContinuousClock()
        let start = clock.now
        let before = trace.evaluated.count
        let inner = scope.entering(node.id, group: definition.id, graph: definition.graph,
                                  bound: EvaluationScope.Bound(values: inputs, key: key))
        let wanted = scope.setup.inspectedNodes(inside: inner.path, of: definition.graph)
        let everything = try await evaluateLevel(definition.graph, demand: wanted.union([output.id]), scope: inner,
                                                 trace: &trace)
        let ran = trace.evaluated.count > before
        let graph = definition.graph
        // Only what feeds Group Output speaks for the group node: messages and states of the nodes asked for to be
        // shown (`inspectedNodes`) stay in `trace`.
        let feeding = Set(graph.evaluationOrder(for: [output.id]).order)
        var level = everything
        level.order = everything.order.filter(feeding.contains)
        if let message = GroupTrail.firstError(in: level, graph: graph, definition: definition) {
            return GroupOutcome(result: NodeResult(state: .error(message)), key: key, ran: ran)
        }
        guard let result = level.results[output.id], result.state.isSuccess, let outputs = result.outputs,
              let outputKey = level.keys[output.id] else {
            let reason = GroupTrail.firstIdleReason(in: level, graph: graph, definition: definition)
            return GroupOutcome(result: NodeResult(state: .idle(reason)), key: key, ran: ran)
        }
        var hasher = Hasher()
        hasher.combine(key)
        hasher.combine(outputKey)
        let warnings = GroupTrail.warnings(in: level, graph: graph, definition: definition)
        let state: NodeState = warnings.isEmpty
            ? .ok(duration: start.duration(to: clock.now)) : .warning(warnings.joined(separator: "\n"))
        return GroupOutcome(result: NodeResult(state: state, outputs: outputs), key: CacheKey(digest: hasher.finalize()), ran: ran)
    }
}
