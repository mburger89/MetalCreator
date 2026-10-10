import CreatorKernel

/// Group Input (groups spec §4): inside a definition, its outputs are the group node's inputs. The evaluator hands it
/// the group node's gathered values unchanged, so `evaluate` is never called.
public enum GroupInputNode: NodeDefinition {
    public static let typeID = GroupNodes.inputTypeID
    public static let displayName = "Group Input"
    public static let category = NodeCategory.value
    public static let inputs: [SocketSpec] = []
    public static let outputs: [SocketSpec] = []

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        throw NodeError.invalidValue("Group Input takes its values from the group node.")
    }
}
