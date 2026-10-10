// Test fixture file: a node whose sockets carry every field the "+" drop must copy.
import CreatorKernel
@testable import CreatorGraph

/// Inputs and outputs that use access, optional, unit and range, for the exposing tests.
enum ExposeProbeNode: NodeDefinition {
    static let typeID = "test.exposeProbe"
    static let displayName = "Expose Probe"
    static let category = NodeCategory.value
    static let inputs = [
        SocketSpec("values", .number, access: .list),
        SocketSpec("maybe", .number, optional: true),
        SocketSpec("length", .number, defaultValue: .number(5), unit: .millimetres, range: 1...20),
    ]
    static let outputs = [SocketSpec("size", .number, unit: .millimetres)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["size": .number(try inputs.number("length"))])
    }
}

/// `testRegistry`'s types and the probe.
let probeRegistry = NodeRegistry([AddNode.self, SumListNode.self, ExposeProbeNode.self])
