import CreatorGeometry
import CreatorKernel
@testable import CreatorGraph

/// Emits one `.length` spec of its `value` per iteration; a negative value makes it throw.
enum SpecEmittingNode: NodeDefinition {
    static let typeID = "test.specEmitting"
    static let displayName = "Spec Emitting"
    static let category = NodeCategory.value
    static let inputs = [SocketSpec("value", .number, defaultValue: .number(0))]
    static let outputs = [SocketSpec("value", .number)]

    /// The spec this node emits for `value`.
    static func spec(_ value: Double) -> DimensionSpec {
        DimensionSpec(.input("value"),
                      .linear(from: Vector3(0, 0, 0), to: Vector3(value, 0, 0), direction: Vector3(1, 0, 0),
                              side: Vector3(0, 1, 0), placement: .standoff),
                      .length, value: value)
    }

    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let value = try inputs.number("value")
        guard value >= 0 else { throw NodeError.invalidValue("Negative") }
        var outputs = NodeOutputs(["value": .number(value)])
        outputs.dimensions = [spec(value)]
        return outputs
    }
}

/// Passes `value` through, and errors "Too big." when it is above 50.
enum ThresholdNode: NodeDefinition {
    static let typeID = "test.threshold"
    static let displayName = "Threshold"
    static let category = NodeCategory.value
    static let inputs = [SocketSpec("value", .number, defaultValue: .number(0))]
    static let outputs = [SocketSpec("value", .number)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let value = try inputs.number("value")
        guard value <= 50 else { throw NodeError.invalidValue("Too big.") }
        return NodeOutputs(["value": .number(value)])
    }
}

/// A gate that holds evaluations of `GatedNode` until `open()`.
actor Gate {
    private var isOpen = false
    func open() { isOpen = true }
    func close() { isOpen = false }
    /// Returns once the gate is open; throws if the waiting task is cancelled.
    func waitUntilOpen() async throws {
        while !isOpen { try await Task.sleep(for: .milliseconds(5)) }
    }
}

/// Passes `value` through once `GatedNode.gate` is open, so a test can look at the document while an evaluation runs.
enum GatedNode: NodeDefinition {
    static let typeID = "test.gated"
    static let displayName = "Gated"
    static let category = NodeCategory.value
    static let inputs = [SocketSpec("value", .number, defaultValue: .number(0))]
    static let outputs = [SocketSpec("value", .number)]
    static let gate = Gate()
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        try await gate.waitUntilOpen()
        return NodeOutputs(["value": .number(try inputs.number("value"))])
    }
}

/// A registry of its own, so `testRegistry`'s node count (asserted elsewhere) stays as it is.
let dimensionTestRegistry = NodeRegistry([
    SpecEmittingNode.self, ListSourceNode.self, ThresholdNode.self, GatedNode.self, ConstantNode.self, WarnNode.self,
])
