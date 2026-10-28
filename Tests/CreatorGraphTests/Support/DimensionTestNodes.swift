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

/// A registry of its own, so `testRegistry`'s node count (asserted elsewhere) stays as it is.
let dimensionTestRegistry = NodeRegistry([SpecEmittingNode.self, ListSourceNode.self])
