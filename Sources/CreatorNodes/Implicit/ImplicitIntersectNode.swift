import CreatorGraph
import CreatorKernel

/// Intersect: only what is in every shape (implicit spec §3.3).
public enum ImplicitIntersectNode: NodeDefinition {
    public static let typeID = "creator.implicitIntersect"
    public static let displayName = "Intersect"
    public static let category = NodeCategory.implicit
    public static let inputs = ImplicitCombining.inputs
    public static let outputs = ImplicitCombining.outputs
    public static let inspector = ImplicitCombining.inspector(displayName)

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        try await ImplicitCombining.evaluate(.intersect, inputs, kernel: kernel, context: context)
    }
}
