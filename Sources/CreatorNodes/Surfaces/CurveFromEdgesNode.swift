import CreatorGraph
import CreatorKernel

/// The edges of a solid or sheet as curves, chained end to end (NURBS spec).
public enum CurveFromEdgesNode: NodeDefinition {
    public static let typeID = "creator.curveFromEdges"
    public static let displayName = "Curve from Edges"
    public static let category = NodeCategory.surface
    public static let librarySubgroup: String? = "Curves"
    public static let inputs = [SocketSpec("edges", .edgeSet)]
    public static let outputs = [SocketSpec("curves", .curve, access: .list)]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let set = try inputs.edgeSet("edges")
        let curves = try await kernel.curves(from: set.edges, of: set.solid, tag: context.tag)
        return NodeOutputs(lists: ["curves": curves.map { .curve($0) }])
    }
}
