import CreatorGraph
import CreatorKernel

/// Puts every item in a branch of its own (7a spec §4), one level deeper: a list of 3 becomes 3 × 1, and a 3 × 8 tree
/// becomes 3 × 8 × 1. A node after it then runs once per item, with each result in its own branch.
public enum GraftNode: NodeDefinition {
    public static let typeID = "creator.graft"
    public static let displayName = "Graft"
    public static let category = NodeCategory.lists
    public static let inputs = [SocketSpec("tree", .any, access: .tree)]
    public static let outputs = [SocketSpec("tree", .any)]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(trees: ["tree": try inputs.tree("tree").grafted()])
    }
}
