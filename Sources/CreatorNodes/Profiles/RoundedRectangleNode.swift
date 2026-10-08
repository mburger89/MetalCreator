import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// A rectangle with rounded corners (spec §7.1, Profiles). Eight segments, counter-clockwise
/// from the bottom edge (`Profile2D.roundedRectangle`). A corner radius of 0 gives a plain
/// four-segment rectangle, so edge picks made on the rounded version won't match it.
public enum RoundedRectangleNode: NodeDefinition {
    public static let typeID = "creator.roundedRectangle"
    public static let displayName = "Rounded Rectangle"
    public static let category = NodeCategory.profile
    public static let inputs = [
        SocketSpec("width", .number, defaultValue: .number(60), unit: .millimetres, range: 0.1...500),
        SocketSpec("height", .number, defaultValue: .number(40), unit: .millimetres, range: 0.1...500),
        SocketSpec("cornerRadius", .number, defaultValue: .number(4), unit: .millimetres, range: 0...50),
        SocketSpec("plane", .plane, defaultValue: .plane(.xy)),
        SocketSpec("anchor", .integer, defaultValue: .integer(Anchor.centre)),
    ]
    public static let outputs = [SocketSpec("profile", .profile)]
    public static let inspector = [
        InspectorSection(title: "Size", controls: [.slider("width"), .slider("height"), .slider("cornerRadius")]),
        InspectorSection(title: "Placement", controls: [.planePicker("plane"), .anchorGrid("anchor")]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let (width, height, radius) = (try inputs.number("width"), try inputs.number("height"), try inputs.number("cornerRadius"))
        try ProfileChecks.positive(width, "width")
        try ProfileChecks.positive(height, "height")
        guard radius.isFinite, radius >= 0 else { throw NodeError.invalidValue("“cornerRadius” can't be negative.") }
        let limit = min(width, height) / 2
        guard radius < limit else {
            throw NodeError.invalidValue("Corner radius \(radius.display) mm is too large for a "
                + "\(width.display) × \(height.display) mm rectangle (it must be less than \(limit.display) mm).")
        }
        let plane = try inputs.plane("plane")
        let offset = try Anchor.offset(try inputs.integer("anchor"), width: width, height: height)
        let centred = radius == 0
            ? Profile2D.rectangle(width: width, height: height, plane: plane)
            : Profile2D.roundedRectangle(width: width, height: height, radius: radius, plane: plane)
        return NodeOutputs(["profile": .profile(centred.translated(by: offset))])
    }
}
