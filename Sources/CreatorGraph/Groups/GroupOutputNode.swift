import CreatorKernel

/// Group Output (groups spec §4): inside a definition, its inputs are the group node's outputs. The evaluator passes
/// what reaches it through unchanged, so `evaluate` is never called. Its inputs are optional: an unwired one is an
/// output the group node doesn't produce.
public enum GroupOutputNode: NodeDefinition {
    public static let typeID = GroupNodes.outputTypeID
    public static let displayName = "Group Output"
    public static let category = NodeCategory.value
    public static let inputs: [SocketSpec] = []
    public static let outputs: [SocketSpec] = []

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        throw NodeError.invalidValue("Group Output hands its values to the group node.")
    }
}
