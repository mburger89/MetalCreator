/// What a node's iterations produced, gathered while it runs and turned into its output values afterwards.
struct IterationOutputs {
    /// What each iteration made of each output: one entry per iteration.
    private var collected: [SocketName: [[Scalar]]] = [:]
    private var trees: [SocketName: DataTree] = [:]
    private var producedList: Set<SocketName> = []
    private var absent: Set<SocketName> = []
    var warnings: [String]

    init(warnings: [String]) {
        self.warnings = warnings
    }

    /// Takes one iteration's outputs. A node that returns a tree must run once: with other inputs broadcasting there
    /// would be several trees and no rule to join them.
    mutating func record(_ outputs: NodeOutputs, specs: [SocketSpec], iterations: Int) throws {
        if !outputs.trees.isEmpty, iterations != 1 {
            throw NodeError.invalidValue(
                "This node works on a whole tree at once, so its other inputs must be single values, not lists.")
        }
        for spec in specs {
            if let tree = outputs.trees[spec.name] {
                trees[spec.name] = tree
            } else if let list = outputs.lists[spec.name] {
                collected[spec.name, default: []].append(list)
                producedList.insert(spec.name)
            } else if let scalar = outputs.values[spec.name] {
                collected[spec.name, default: []].append([scalar])
            } else if spec.isOptional {
                absent.insert(spec.name)
            } else {
                throw NodeError.invalidValue("The node didn't produce its “\(spec.name)” output.")
            }
        }
        warnings += outputs.warnings
    }

    /// The output values. An optional output that any iteration left out is absent.
    func values(for specs: [SocketSpec], plan: BroadcastPlan) -> [SocketName: Value] {
        var outputs: [SocketName: Value] = [:]
        for spec in specs where !absent.contains(spec.name) {
            if let tree = trees[spec.name] {
                outputs[spec.name] = Value(tree)
            } else {
                outputs[spec.name] = plan.assemble(collected[spec.name] ?? [], producedList: producedList.contains(spec.name))
            }
        }
        return outputs
    }
}
