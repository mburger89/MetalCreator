import CreatorKernel

/// A group node (groups spec §4): its sockets are its definition's (`NodeRegistry.inputs(for:)`/`outputs(for:)`), and
/// the evaluator runs the definition's graph in its place, so `evaluate` is never called.
public enum GroupNode: NodeDefinition {
    public static let typeID = GroupNodes.groupTypeID
    public static let displayName = "Group"
    public static let category = NodeCategory.feature
    public static let inputs: [SocketSpec] = []
    public static let outputs: [SocketSpec] = []

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        throw NodeError.invalidValue("A group is evaluated through its definition's graph.")
    }
}
