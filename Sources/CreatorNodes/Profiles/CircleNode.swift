import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// A circle centred on its plane's origin (spec §7.1, Profiles). Wire points into `plane` to
/// place one circle per point (a vector becomes the XY plane through it, spec §4.2).
public enum CircleNode: NodeDefinition {
    public static let typeID = "creator.circle"
    public static let displayName = "Circle"
    public static let category = NodeCategory.profile
    public static let inputs = [
        SocketSpec("diameter", .number, defaultValue: .number(10), unit: .millimetres, range: 0.1...500),
        SocketSpec("plane", .plane, defaultValue: .plane(.xy)),
    ]
    public static let outputs = [SocketSpec("profile", .profile)]
    public static let inspector = [
        InspectorSection(title: "Size", controls: [.slider("diameter")]),
        InspectorSection(title: "Placement", controls: [.planePicker("plane")]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let diameter = try inputs.number("diameter")
        try ProfileChecks.positive(diameter, "diameter")
        let profile = Profile2D.circle(radius: diameter / 2, center: .zero, plane: try inputs.plane("plane"))
        return NodeOutputs(["profile": .profile(profile)])
    }
}
