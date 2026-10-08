import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// A rectangle on a plane (spec §7.1, Profiles). Four segments, counter-clockwise from the bottom
/// edge: bottom (side 0), right (1), top (2), left (3).
public enum RectangleNode: NodeDefinition {
    public static let typeID = "creator.rectangle"
    public static let displayName = "Rectangle"
    public static let category = NodeCategory.profile
    public static let inputs = [
        SocketSpec("width", .number, defaultValue: .number(20), unit: .millimetres, range: 0.1...500),
        SocketSpec("height", .number, defaultValue: .number(10), unit: .millimetres, range: 0.1...500),
        SocketSpec("plane", .plane, defaultValue: .plane(.xy)),
        SocketSpec("anchor", .integer, defaultValue: .integer(Anchor.centre)),
    ]
    public static let outputs = [SocketSpec("profile", .profile)]
    public static let inspector = [
        InspectorSection(title: "Size", controls: [.slider("width"), .slider("height")]),
        InspectorSection(title: "Placement", controls: [.planePicker("plane"), .anchorGrid("anchor")]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let (width, height) = (try inputs.number("width"), try inputs.number("height"))
        try ProfileChecks.positive(width, "width")
        try ProfileChecks.positive(height, "height")
        let offset = try Anchor.offset(try inputs.integer("anchor"), width: width, height: height)
        let profile = Profile2D.rectangle(width: width, height: height, plane: try inputs.plane("plane")).translated(by: offset)
        return NodeOutputs(["profile": .profile(profile)])
    }
}
