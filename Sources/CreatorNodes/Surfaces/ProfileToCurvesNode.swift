import CreatorGraph
import CreatorKernel

/// A profile's loops as curves: the outer loop, then each hole (NURBS spec).
public enum ProfileToCurvesNode: NodeDefinition {
    public static let typeID = "creator.profileToCurves"
    public static let displayName = "Profile to Curves"
    public static let category = NodeCategory.surface
    public static let librarySubgroup: String? = "Curves"
    public static let inputs = [SocketSpec("profile", .profile)]
    public static let outputs = [SocketSpec("curves", .curve, access: .list)]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let curves = try await CurveInput.loops([.profile(try inputs.profile("profile"))], holes: .all, kernel: kernel,
                                                tag: context.tag)
        return NodeOutputs(lists: ["curves": curves.map { .curve($0) }])
    }
}
