import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel

/// A wall of `thickness` on one side of an implicit solid's surface (implicit spec §3.3): inside it, outside it or centred on it.
/// The thickness is a field, so a 7b field can grade it; it is sampled per point by the solid's own evaluator.
public enum ImplicitShellNode: NodeDefinition {
    public static let typeID = "creator.implicitShell"
    public static let displayName = "Shell"
    public static let category = NodeCategory.implicit
    public static let inputs = [
        SocketSpec("implicit", .implicit),
        SocketSpec("thickness", .field, defaultValue: .number(2), unit: .millimetres, range: 0...50),
        SocketSpec("side", .integer, defaultValue: .integer(ShellSide.inward.rawValue)),
    ]
    public static let outputs = [SocketSpec("implicit", .implicit)]
    public static let inspector = [
        InspectorSection(title: "Shell", controls: [.segmented("side", options: ShellSide.options), .number("thickness")]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let child = try inputs.implicitSolid("implicit")
        // `choice` refuses an index outside the options, so every index it returns is a side.
        let side = ShellSide(rawValue: try inputs.choice("side", options: ShellSide.options)) ?? .inward
        let setting = try await ImplicitGrading.make(try inputs.field("thickness"), named: "thickness",
                                                     over: ImplicitGrading.region(around: child.bounds), holdsAtZero: true,
                                                     kernel: kernel, context: context)
        let result = ImplicitSolid.shell(child, thickness: setting.grading, side: side)
        let reach = ImplicitReach.shellReach(thickness: setting.grading.magnitude, side: side)
        return NodeOutputs(["implicit": .implicit(result.reference)],
                           warnings: setting.warnings + ImplicitReach.warnings(for: child, reachedBy: reach))
    }
}
