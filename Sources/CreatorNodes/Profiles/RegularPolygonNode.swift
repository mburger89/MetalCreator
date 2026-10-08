import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// A regular polygon about its plane's origin (spec §7.1, Profiles). `radius` is the circumradius. The first
/// corner is on +x, turned counter-clockwise by `rotation` (M6: spec §8's polygon swap needs a hexagon turned
/// 30°, whose sides then run parallel to the plane's y axis). Version 2 added `rotation`. A version-1 node has
/// no stored rotation and reads the default 0°, so it needs no migration. `makeNode` stamps version 2, so an
/// older build refuses to evaluate any polygon saved by M6 or later, rather than drawing a rotated one unrotated.
public enum RegularPolygonNode: NodeDefinition {
    public static let typeID = "creator.regularPolygon"
    public static let typeVersion = 2
    public static let displayName = "Regular Polygon"
    public static let category = NodeCategory.profile
    public static let maximumSides = 1000
    public static let inputs = [
        SocketSpec("sides", .integer, defaultValue: .integer(6), unit: .count),
        SocketSpec("radius", .number, defaultValue: .number(10), unit: .millimetres, range: 0.1...250),
        SocketSpec("rotation", .number, defaultValue: .number(0), unit: .degrees, range: -180...180),
        SocketSpec("plane", .plane, defaultValue: .plane(.xy)),
    ]
    public static let outputs = [SocketSpec("profile", .profile)]
    public static let inspector = [
        InspectorSection(title: "Shape", controls: [.integer("sides"), .slider("radius"), .slider("rotation")]),
        InspectorSection(title: "Placement", controls: [.planePicker("plane")]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let (sides, radius) = (try inputs.integer("sides"), try inputs.number("radius"))
        guard (3...maximumSides).contains(sides) else {
            throw NodeError.invalidValue("A polygon needs 3 to \(maximumSides.display) sides.")
        }
        try ProfileChecks.positive(radius, "radius")
        let profile = Profile2D.regularPolygon(sides: sides, radius: radius, rotation: .degrees(try inputs.number("rotation")),
                                               plane: try inputs.plane("plane"))
        return NodeOutputs(["profile": .profile(profile)])
    }
}
