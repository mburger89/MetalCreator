import CreatorGraph
import CreatorKernel

/// Union: everything in any of the shapes (implicit spec §3.3). The smooth minimum rounds the joins by the blend radius.
public enum ImplicitUnionNode: NodeDefinition {
    public static let typeID = "creator.implicitUnion"
    public static let displayName = "Union"
    public static let category = NodeCategory.implicit
    public static let inputs = ImplicitCombining.inputs
    public static let outputs = ImplicitCombining.outputs
    public static let inspector = ImplicitCombining.inspector(displayName)

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        try await ImplicitCombining.evaluate(.union, inputs, kernel: kernel, context: context)
    }
}
