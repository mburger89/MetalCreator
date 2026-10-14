import CreatorGraph
import CreatorKernel

/// Subtract: the first shape with all the others cut away (implicit spec §3.3).
public enum ImplicitSubtractNode: NodeDefinition {
    public static let typeID = "creator.implicitSubtract"
    public static let displayName = "Subtract"
    public static let category = NodeCategory.implicit
    public static let inputs = ImplicitCombining.inputs
    public static let outputs = ImplicitCombining.outputs
    public static let inspector = ImplicitCombining.inspector(displayName)

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        try await ImplicitCombining.evaluate(.subtract, inputs, kernel: kernel, context: context)
    }
}
