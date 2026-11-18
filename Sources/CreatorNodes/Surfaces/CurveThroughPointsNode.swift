import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// A smooth curve through a list of points, of degree 3 or 5 (NURBS spec). Degree 5 takes no end tangents and no closing,
/// which the kernel says in its own words.
public enum CurveThroughPointsNode: NodeDefinition {
    public static let typeID = "creator.curveThroughPoints"
    public static let displayName = "Curve through Points"
    public static let category = NodeCategory.surface
    public static let librarySubgroup: String? = "Curves"
    public static let maximumPoints = 10_000
    public static let degrees = ["3", "5"]
    public static let inputs = [
        SocketSpec("points", .vector, access: .list, unit: .millimetres),
        SocketSpec("degree", .integer, defaultValue: .integer(0)),
        SocketSpec("closed", .bool, defaultValue: .bool(false)),
        SocketSpec("start tangent", .vector, optional: true),
        SocketSpec("end tangent", .vector, optional: true),
    ]
    public static let outputs = [SocketSpec("curve", .curve)]
    public static let inspector = [InspectorSection(title: "Curve", controls: [
        .segmented("degree", options: degrees), .toggle("closed", label: "Closed"),
        .vector("start tangent"), .vector("end tangent"),
    ]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let points = try inputs.list("points").map { scalar -> Vector3 in
            guard case .vector(let point) = scalar else { throw NodeError.typeMismatch("points", expected: .vector) }
            return point
        }
        guard points.count >= 2 else { throw NodeError.invalidValue("A curve needs at least two points.") }
        guard points.count <= maximumPoints else {
            throw NodeError.invalidValue("Curve through Points takes at most \(maximumPoints.display) points.")
        }
        let degree = try inputs.choice("degree", options: degrees) == 0 ? 3 : 5
        let start = inputs.has("start tangent") ? try inputs.vector("start tangent") : nil
        let end = inputs.has("end tangent") ? try inputs.vector("end tangent") : nil
        let curve = try await kernel.interpolate(points, degree: degree, closed: try inputs.bool("closed"), startTangent: start,
                                                 endTangent: end, tag: context.tag)
        return NodeOutputs(["curve": .curve(curve)])
    }
}
