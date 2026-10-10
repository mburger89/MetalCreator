import CreatorKernel

extension Evaluator {
    enum Gathered {
        case ready([SocketName: Value], CacheKey)
        case blocked(String)
        case failed(String)
    }

    // Gathers a node's inputs (wire, else typed value, else the socket's default) and builds its cache key in the
    // same pass, naming the node by the identity it evaluates under (`EvaluationScope.identity(of:)`).
    // One pass over the inputs that also builds the cache key; one branch over the limit.
    // swiftlint:disable:next cyclomatic_complexity
    func gather(_ node: Node, _ definition: any NodeDefinition.Type, graph: Graph, level: EvaluationLevel,
                scope: EvaluationScope) -> Gathered {
        let setup = scope.setup
        var inputs: [SocketName: Value] = [:]
        var hasher = Hasher()
        // Output depends on node identity: the kernel tags created faces with it.
        hasher.combine(scope.identity(of: node.id))
        hasher.combine(node.typeID)
        hasher.combine(node.typeVersion)
        // Every stored constant, including non-socket settings, sorted for determinism.
        for (name, value) in node.inputValues.sorted(by: { $0.key < $1.key }) {
            hasher.combine(name)
            hasher.combine(value)
        }
        if definition.readsParameters {
            for (id, value) in setup.parameters.sorted(by: { $0.key < $1.key }) {
                hasher.combine(id)
                hasher.combine(value)
            }
        }

        for spec in setup.registry.inputs(for: node) {
            if let link = graph.incomingLink(to: Endpoint(node: node.id, socket: spec.name)) {
                guard let upstream = level.results[link.from.node], upstream.state.isSuccess, let outputs = upstream.outputs else {
                    return .blocked("Waiting on “\(spec.name)”: the node wired into it has no result.")
                }
                guard let value = outputs[link.from.socket] else {
                    return .failed("“\(spec.name)” is wired to “\(link.from.socket)”, "
                        + "which that node doesn't produce with its current settings.")
                }
                guard let converted = value.converted(to: spec.type) else {
                    return .failed("“\(spec.name)” needs \(spec.type.indefiniteName).")
                }
                inputs[spec.name] = converted
                hasher.combine(spec.name)
                hasher.combine(level.keys[link.from.node])
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

    /// Runs a node once per broadcast item. `node` carries the identity it evaluates under.
    func run(_ definition: any NodeDefinition.Type, node: Node, inputs: [SocketName: Value],
             setup: EvaluationSetup) async throws -> NodeResult {
        let plan = BroadcastPlan.make(inputs: inputs, specs: setup.registry.inputs(for: node))
        let outputSpecs = setup.registry.outputs(for: node)
        let clock = ContinuousClock()
        let start = clock.now
        var collected: [SocketName: [Scalar]] = [:]
        var producedList: Set<SocketName> = []
        var absent: Set<SocketName> = []
        var warnings: [String] = []
        do {
            for item in 0..<plan.iterations {
                try Task.checkCancellation()
                let context = EvalContext(node: node, item: item, parameters: setup.parameters)
                let outputs = try await definition.evaluate(plan.inputs(at: item), kernel: kernel, context: context)
                for spec in outputSpecs {
                    if let list = outputs.lists[spec.name] {
                        collected[spec.name, default: []] += list
                        producedList.insert(spec.name)
                    } else if let scalar = outputs.values[spec.name] {
                        collected[spec.name, default: []].append(scalar)
                    } else if spec.isOptional {
                        absent.insert(spec.name)
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
        // An optional output that any iteration left out is absent from the result.
        for spec in outputSpecs where !absent.contains(spec.name) {
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
