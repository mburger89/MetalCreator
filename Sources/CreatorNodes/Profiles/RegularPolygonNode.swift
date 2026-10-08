import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// A regular polygon about its plane's origin, first corner on +x (spec §7.1, Profiles).
/// `radius` is the circumradius.
public enum RegularPolygonNode: NodeDefinition {
    public static let typeID = "creator.regularPolygon"
    public static let displayName = "Regular Polygon"
    public static let category = NodeCategory.profile
    public static let maximumSides = 1000
    public static let inputs = [
        SocketSpec("sides", .integer, defaultValue: .integer(6), unit: .count),
        SocketSpec("radius", .number, defaultValue: .number(10), unit: .millimetres, range: 0.1...250),
        SocketSpec("plane", .plane, defaultValue: .plane(.xy)),
    ]
    public static let outputs = [SocketSpec("profile", .profile)]
    public static let inspector = [
        InspectorSection(title: "Shape", controls: [.integer("sides"), .slider("radius")]),
        InspectorSection(title: "Placement", controls: [.planePicker("plane")]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let (sides, radius) = (try inputs.integer("sides"), try inputs.number("radius"))
        guard (3...maximumSides).contains(sides) else {
            throw NodeError.invalidValue("A polygon needs 3 to \(maximumSides.display) sides.")
        }
        try ProfileChecks.positive(radius, "radius")
        let profile = Profile2D.regularPolygon(sides: sides, radius: radius, plane: try inputs.plane("plane"))
        return NodeOutputs(["profile": .profile(profile)])
    }
}
