import CreatorGraph
import CreatorKernel

/// Every edge of a solid except seams (spec §7.1, Selection).
public enum AllEdgesNode: NodeDefinition {
    public static let typeID = "creator.allEdges"
    public static let displayName = "All Edges"
    public static let category = NodeCategory.selection
    public static let inputs = [SocketSpec("solid", .solid)]
    public static let outputs = [SocketSpec("edges", .edgeSet)]
    public static let inspector = [InspectorSection(title: "Edges", controls: [.ruleSummary("edges")])]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let solid = try inputs.solid("solid")
        return EdgeSelection.outputs(solid, EdgeSelection.candidates(solid).map(\.id))
    }
}
