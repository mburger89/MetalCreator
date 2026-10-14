import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel

/// Moves an implicit solid's surface by `distance`, outwards when positive and inwards when negative (implicit spec §3.3). The
/// distance is a field, so a 7b field can grade it.
public enum ImplicitOffsetNode: NodeDefinition {
    public static let typeID = "creator.implicitOffset"
    public static let displayName = "Offset"
    public static let category = NodeCategory.implicit
    public static let inputs = [
        SocketSpec("implicit", .implicit),
        SocketSpec("distance", .field, defaultValue: .number(1), unit: .millimetres, range: -50...50),
    ]
    public static let outputs = [SocketSpec("implicit", .implicit)]
    public static let inspector = [InspectorSection(title: "Offset", controls: [.number("distance")])]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let child = try inputs.implicitSolid("implicit")
        let setting = try await ImplicitGrading.make(try inputs.field("distance"), named: "distance",
                                                     over: ImplicitGrading.region(around: child.bounds), holdsAtZero: false,
                                                     kernel: kernel, context: context)
        let result = ImplicitSolid.offset(child, distance: setting.grading)
        return NodeOutputs(["implicit": .implicit(result.reference)],
                           warnings: setting.warnings + ImplicitReach.warnings(for: child, reachedBy: setting.grading.magnitude))
    }
}
