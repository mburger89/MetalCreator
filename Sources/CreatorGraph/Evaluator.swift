import CreatorKernel

/// Evaluates the part of a graph a demand set needs, upstream first, caching each node's
/// result (spec §4.4). It throws only `CancellationError`. Every other failure becomes a
/// node state.
public actor Evaluator {
    private let registry: NodeRegistry
    private let kernel: any Kernel
    private var cache: ResultCache

    public init(registry: NodeRegistry, kernel: any Kernel, cacheBudgetBytes: Int = 512 * 1024 * 1024) {
        self.registry = registry
        self.kernel = kernel
        self.cache = ResultCache(budgetBytes: cacheBudgetBytes)
    }

    public var cachedEntryCount: Int { cache.count }

    public func evaluate(_ graph: Graph, demand: Set<NodeID>) async throws -> EvaluationReport {
        cache.removeEntries(notIn: Set(graph.nodes.keys))
        let plan = graph.evaluationOrder(for: demand)
        let parameters = Dictionary(graph.parameters.map { ($0.id, $0.value) }, uniquingKeysWith: { first, _ in first })
        var results: [NodeID: NodeResult] = [:]
        var keys: [NodeID: CacheKey] = [:]
        var evaluated: [NodeID] = []

        for id in plan.order {
            try Task.checkCancellation()
            guard let node = graph.nodes[id] else { continue }
            if plan.cyclic.contains(id) {
                results[id] = NodeResult(state: .error("This node is part of a cycle. Remove one of the wires in the loop."))
                continue
            }
            guard let definition = registry[node.typeID] else {
                results[id] = NodeResult(state: .error("Unknown node type “\(node.typeID)”. It's kept so the file isn't damaged."))
                continue
            }
            switch gather(node, definition, graph: graph, results: results, keys: keys, parameters: parameters) {
            case .blocked(let reason):
                results[id] = NodeResult(state: .idle(reason))
            case .failed(let message):
                results[id] = NodeResult(state: .error(message))
            case .ready(let inputs, let key):
                keys[id] = key
                if let cached = cache.result(for: key) {
                    results[id] = cached
                    continue
                }
                let result = try await run(definition, node: node, inputs: inputs, parameters: parameters)
                evaluated.append(id)
                results[id] = result
                if result.state.isSuccess {
                    cache.insert(result, for: key, node: id)
                }
            }
        }
        return EvaluationReport(results: results, evaluatedNodes: evaluated)
    }

    // MARK: - Inputs

    private enum Gathered {
        case ready([SocketName: Value], CacheKey)
        case blocked(String)
        case failed(String)
    }

    private func gather(_ node: Node, _ definition: any NodeDefinition.Type, graph: Graph,
                        results: [NodeID: NodeResult], keys: [NodeID: CacheKey],
                        parameters: [ParameterID: ConstantValue]) -> Gathered {
        var inputs: [SocketName: Value] = [:]
        var hasher = Hasher()
        // Output depends on node identity: the kernel tags created faces with it.
        hasher.combine(node.id)
        hasher.combine(node.typeID)
        hasher.combine(node.typeVersion)
        // Every stored constant, including non-socket settings, sorted for determinism.
        for (name, value) in node.inputValues.sorted(by: { $0.key < $1.key }) {
            hasher.combine(name)
            hasher.combine(value)
        }
        if definition.readsParameters {
            for (id, value) in parameters.sorted(by: { $0.key < $1.key }) {
                hasher.combine(id)
                hasher.combine(value)
            }
        }

        for spec in definition.inputs {
            if let link = graph.incomingLink(to: Endpoint(node: node.id, socket: spec.name)) {
                guard let upstream = results[link.from.node], upstream.state.isSuccess,
                      let value = upstream.outputs?[link.from.socket] else {
                    return .blocked("Waiting on “\(spec.name)”: the node wired into it has no result.")
                }
                guard let converted = value.converted(to: spec.type) else {
                    return .failed("“\(spec.name)” needs a \(spec.type.rawValue).")
                }
                inputs[spec.name] = converted
                hasher.combine(spec.name)
                hasher.combine(keys[link.from.node])
                hasher.combine(link.from.socket)
            } else if let constant = node.inputValues[spec.name] ?? spec.defaultValue {
                guard let scalar = Scalar(constant)?.converted(to: spec.type) else {
                    return .failed("“\(spec.name)” has a value of the wrong type.")
                }
                inputs[spec.name] = .one(scalar)
                hasher.combine(spec.defaultValue)
            } else if !spec.isOptional {
                return .blocked(NodeError.missingInput(spec.name).message)
            }
        }
        return .ready(inputs, CacheKey(digest: hasher.finalize()))
    }

    // MARK: - Running

    private func run(_ definition: any NodeDefinition.Type, node: Node, inputs: [SocketName: Value],
                     parameters: [ParameterID: ConstantValue]) async throws -> NodeResult {
        let plan = BroadcastPlan.make(inputs: inputs, specs: definition.inputs)
        let clock = ContinuousClock()
        let start = clock.now
        var collected: [SocketName: [Scalar]] = [:]
        var producedList: Set<SocketName> = []
        var warnings: [String] = []
        do {
            for item in 0..<plan.iterations {
                try Task.checkCancellation()
                let context = EvalContext(node: node, item: item, parameters: parameters)
                let outputs = try await definition.evaluate(plan.inputs(at: item), kernel: kernel, context: context)
                for spec in definition.outputs {
                    if let list = outputs.lists[spec.name] {
                        collected[spec.name, default: []] += list
                        producedList.insert(spec.name)
                    } else if let scalar = outputs.values[spec.name] {
                        collected[spec.name, default: []].append(scalar)
                    } else {
                        throw NodeError.invalidValue("The node didn't produce its “\(spec.name)” output.")
                    }
                }
                warnings += outputs.warnings
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // A node aborted by cancellation may throw something else; don't record that as an error.
            try Task.checkCancellation()
            return NodeResult(state: .error(Self.message(for: error)))
        }

        var outputs: [SocketName: Value] = [:]
        for spec in definition.outputs {
            let scalars = collected[spec.name] ?? []
            if plan.isSingle, !producedList.contains(spec.name), let only = scalars.first, scalars.count == 1 {
                outputs[spec.name] = .one(only)
            } else {
                outputs[spec.name] = .list(scalars)
            }
        }
        let unique = Array(Set(warnings)).sorted()
        let state: NodeState = unique.isEmpty ? .ok(duration: start.duration(to: clock.now)) : .warning(unique.joined(separator: "\n"))
        return NodeResult(state: state, outputs: outputs)
    }

    /// Plain-language text for any error a node can throw.
    public static func message(for error: any Error) -> String {
        switch error {
        case let error as KernelError: error.userMessage
        case let error as NodeError: error.message
        default: String(describing: error)
        }
    }
}
