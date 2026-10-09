// Test fixture file: a node whose handle drives a per-node socket, as an exposed sketch dimension is one.
import CreatorGraph
import CreatorKernel
import CreatorNodes

/// A `profile` input plus a per-node `size` number socket (`inputs(for:)` only, default 8, 0…50) with a linear handle,
/// so the handle builder and the drag's no-op check must read `inputs(for:)` to find it.
enum PerNodeHandleTestNode: NodeDefinition {
    static let typeID = "apptest.perNodeHandle"
    static let displayName = "Per-node Handle"
    static let category = NodeCategory.solid
    static let inputs = [SocketSpec("profile", .profile)]
    static let outputs: [SocketSpec] = []
    static let handles: [HandleSpec] = [.linear("size")]
    static func inputs(for node: Node) -> [SocketSpec] {
        inputs + [SocketSpec("size", .number, defaultValue: .number(8), unit: .millimetres, range: 0...50)]
    }
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs([:])
    }

    /// The built-in nodes plus this one.
    static let registry = NodeRegistry(BuiltInNodes.all + [PerNodeHandleTestNode.self])
}
