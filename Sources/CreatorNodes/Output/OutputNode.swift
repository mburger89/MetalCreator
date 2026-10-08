import CreatorGraph
import CreatorKernel

/// Marks solids for preview and export (spec §7.1, Output). The node's name is the export name.
/// It passes every wired solid through as one list. Its `.output` category makes
/// `NodeRegistry.makeNode` flag new Output nodes with `isOutput`, so they join the evaluation
/// demand (spec §4.4) however they are created.
public enum OutputNode: NodeDefinition {
    public static let typeID = "creator.output"
    public static let displayName = "Output"
    public static let category = NodeCategory.output
    public static let inputs = [SocketSpec("solid", .solid, access: .list)]
    public static let outputs = [SocketSpec("solid", .solid)]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let solids = try inputs.solids("solid")
        return NodeOutputs(lists: ["solid": solids.map(Scalar.solid)],
                           warnings: solids.isEmpty ? ["There is nothing to preview or export."] : [])
    }
}
