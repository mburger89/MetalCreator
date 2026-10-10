import CreatorKernel

/// Evaluates the part of a graph a demand set needs, upstream first, caching each node's
/// result (spec §4.4). It throws only `CancellationError`. Every other failure becomes a
/// node state. A group node runs its definition's graph (groups spec §5, `Evaluator+Groups`).
public actor Evaluator {
    let registry: NodeRegistry
    let kernel: any Kernel
    private var cache: ResultCache

    public init(registry: NodeRegistry, kernel: any Kernel, cacheBudgetBytes: Int = 512 * 1024 * 1024) {
        self.registry = registry
        self.kernel = kernel
        self.cache = ResultCache(budgetBytes: cacheBudgetBytes)
    }

    public var cachedEntryCount: Int { cache.count }

    /// Evaluates `demand` on the top level of `graph`; group nodes run the graphs of `definitions`. With `inspecting`,
    /// the group nodes entered from the top level down to the level the graph panel shows (groups spec §6), every
    /// node of that level is evaluated too, so each has a state in `innerResults` even when nothing downstream
    /// wants it; a node there that fails doesn't fail the group node unless it feeds Group Output.
    public func evaluate(_ graph: Graph, definitions: [GroupID: GroupDefinition] = [:], demand: Set<NodeID>,
                         inspecting level: [NodeID] = []) async throws -> EvaluationReport {
        // Entries of nodes no longer anywhere (deleted, or inside a group node that's gone) leave the cache.
        cache.removeEntries(notIn: graph.scopedNodeIDs(definitions: definitions))
        let parameters = Dictionary(graph.parameters.map { ($0.id, $0.value) }, uniquingKeysWith: { first, _ in first })
        let setup = EvaluationSetup(registry: registry.withGroups(definitions), parameters: parameters, inspected: level)
        var trace = EvaluationTrace()
        var demand = demand
        if let first = level.first, graph.nodes[first] != nil { demand.insert(first) }
        let level = try await evaluateLevel(graph, demand: demand, scope: EvaluationScope(setup: setup), trace: &trace)
        return EvaluationReport(results: level.results, evaluatedNodes: level.evaluated, innerResults: trace.results,
                                evaluatedInnerNodes: trace.evaluated)
    }

    /// One level: the top-level graph, or a definition's graph inside a group node (`scope`). Cancellation is
    /// checked before every node, so inside groups too.
    func evaluateLevel(_ graph: Graph, demand: Set<NodeID>, scope: EvaluationScope,
                       trace: inout EvaluationTrace) async throws -> EvaluationLevel {
        let plan = graph.evaluationOrder(for: demand)
        var level = EvaluationLevel(order: plan.order)
        for id in plan.order {
            try Task.checkCancellation()
            guard let node = graph.nodes[id] else { continue }
            let result = plan.cyclic.contains(id)
                ? NodeResult(state: .error("This node is part of a cycle. Remove one of the wires in the loop."))
                : try await evaluateNode(node, in: graph, scope: scope, level: &level, trace: &trace)
            level.results[id] = result
            if !scope.path.isEmpty { trace.results[scope.path + [id]] = result }
        }
        return level
    }

    // One node of a level. One branch per kind of outcome (Group Input, unknown or newer type, the three gather
    // results, a group node, Group Output, any other node), which is over the limit.
    // swiftlint:disable:next cyclomatic_complexity
    private func evaluateNode(_ node: Node, in graph: Graph, scope: EvaluationScope,
                              level: inout EvaluationLevel, trace: inout EvaluationTrace) async throws -> NodeResult {
        if node.typeID == GroupNodes.inputTypeID {
            guard let bound = scope.bound else { return NodeResult(state: .error("Group Input works only inside a group.")) }
            level.keys[node.id] = bound.key
            return NodeResult(state: .ok(duration: .zero), outputs: bound.values)
        }
        guard let definition = scope.setup.registry[node.typeID] else {
            return NodeResult(state: .error("Unknown node type “\(node.typeID)”. It's kept so the file isn't damaged."))
        }
        if node.typeVersion > definition.typeVersion {
            return NodeResult(state: .error(
                "This node was saved by a newer MetalCreator (version \(node.typeVersion)). It's kept unchanged."))
        }
        // Picks stored inside a definition name faces as if it were the top level; read them as this instance's.
        let node = scope.naming(node)
        switch gather(node, definition, graph: graph, level: level, scope: scope) {
        case .blocked(let reason):
            return NodeResult(state: .idle(reason))
        case .failed(let message):
            return NodeResult(state: .error(message))
        case .ready(let inputs, let key):
            switch node.typeID {
            case GroupNodes.groupTypeID:
                let outcome = try await evaluateGroup(node, inputs: inputs, key: key, scope: scope, trace: &trace)
                level.keys[node.id] = outcome.key
                if outcome.ran { level.evaluated.append(node.id) }
                return outcome.result
            case GroupNodes.outputTypeID:
                // Values pass through unchanged; the group node takes them as its outputs.
                level.keys[node.id] = key
                return NodeResult(state: .ok(duration: .zero), outputs: inputs)
            default:
                level.keys[node.id] = key
                if let cached = cache.result(for: key) { return cached }
                var scoped = node
                scoped.id = scope.identity(of: node.id)  // Tags name the node this way (`EvalContext.tag`).
                let result = try await run(definition, node: scoped, inputs: inputs, setup: scope.setup)
                level.evaluated.append(node.id)
                if !scope.path.isEmpty { trace.evaluated.append(scope.path + [node.id]) }
                if result.state.isSuccess {
                    cache.insert(result, for: key, node: scoped.id)
                }
                return result
            }
        }
    }
}
