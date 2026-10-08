import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Straight segments through a list of points (spec §7.1, Profiles). Points are plane
/// coordinates: x and y place each point on `plane`, and z must be 0 (a non-zero z gives a
/// warning, never a silent change). An open polyline is a valid profile, but solids need it closed.
/// A closing point equal to the first is dropped, since `closed` already adds that segment.
public enum PolylineNode: NodeDefinition {
    public static let typeID = "creator.polyline"
    public static let displayName = "Polyline"
    public static let category = NodeCategory.profile
    public static let inputs = [
        SocketSpec("points", .vector, access: .list),
        SocketSpec("closed", .bool, defaultValue: .bool(true)),
        SocketSpec("plane", .plane, defaultValue: .plane(.xy)),
    ]
    public static let outputs = [SocketSpec("profile", .profile)]
    public static let inspector = [
        InspectorSection(title: "Shape", controls: [.toggle("closed", label: "Closed")]),
        InspectorSection(title: "Placement", controls: [.planePicker("plane")]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let vectors = try inputs.vectors("points")
        let closed = try inputs.bool("closed")
        var points = vectors.map { Vector2($0.x, $0.y) }
        if closed, points.count > 1, let first = points.first, let last = points.last, (last - first).length <= 1e-9 {
            points.removeLast()
        }
        guard points.count >= (closed ? 3 : 2) else {
            throw NodeError.invalidValue(closed ? "A closed polyline needs at least 3 points." : "A polyline needs at least 2 points.")
        }
        for index in points.indices.dropFirst() where (points[index] - points[index - 1]).length <= 1e-9 {
            throw NodeError.invalidValue("Points \(index) and \(index + 1) are in the same place.")
        }
        let profile = Profile2D.polyline(points, closed: closed, plane: try inputs.plane("plane"))
        let warnings = vectors.contains { abs($0.z) > 1e-9 }
            ? ["Point z values are ignored: points are placed on the plane by their x and y."] : []
        return NodeOutputs(["profile": .profile(profile)], warnings: warnings)
    }
}
