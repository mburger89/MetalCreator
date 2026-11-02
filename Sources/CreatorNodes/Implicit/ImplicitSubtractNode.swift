import CreatorGraph
import CreatorKernel

/// Subtract: the first shape with all the others cut away (implicit spec §3.3).
public enum ImplicitSubtractNode: NodeDefinition {
    public static let typeID = "creator.implicitSubtract"
    /// 2: `continuity`. A node saved as version 1 reads G1, the smooth minimum it was made with.
    public static let typeVersion = 2
    public static let displayName = "Subtract"
    public static let category = NodeCategory.implicit
    public static let inputs = ImplicitCombining.inputs
    public static let outputs = ImplicitCombining.outputs
    public static let inspector = ImplicitCombining.inspector(displayName)

    public static func migrate(_ node: Node, from version: Int) -> Node { ImplicitCombining.continuityMigration(node) }

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        try await ImplicitCombining.evaluate(.subtract, inputs, kernel: kernel, context: context)
    }
}
