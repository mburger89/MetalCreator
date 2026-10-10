import CreatorKernel
@testable import CreatorGraph

/// Emits the list true, false as one list-valued output, to broadcast a flag over two items. Not in `testRegistry`
/// (a test that counts that registry's nodes would change); a test that needs it builds its own registry.
enum BoolListNode: NodeDefinition {
    static let typeID = "test.boolList"
    static let displayName = "Bool List"
    static let category = NodeCategory.value
    static let inputs: [SocketSpec] = []
    static let outputs = [SocketSpec("flags", .bool)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(lists: ["flags": [.bool(true), .bool(false)]])
    }
}
