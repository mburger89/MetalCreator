import CreatorGraph
import CreatorKernel

/// The curves where two bodies meet, chained into curves and ordered by where they start (NS-4, R14).
public enum IntersectionCurvesNode: NodeDefinition {
    public static let typeID = "creator.intersectionCurves"
    public static let displayName = "Intersection Curves"
    public static let category = NodeCategory.surface
    public static let librarySubgroup: String? = "Curves"
    public static let inputs = [SocketSpec("a", .solid), SocketSpec("b", .solid)]
    public static let outputs = [SocketSpec("curves", .curve, access: .list)]

    public static let noMeeting = "The bodies don't meet, so there are no intersection curves."

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let a = try inputs.solid("a")
        let b = try inputs.solid("b")
        let curves = try await kernel.intersectionCurves(a, b, tag: context.tag)
        return NodeOutputs(lists: ["curves": curves.map { .curve($0) }], warnings: curves.isEmpty ? [noMeeting] : [])
    }
}
