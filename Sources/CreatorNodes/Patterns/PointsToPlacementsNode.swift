import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Points in, placements out (patterns spec §3): each point becomes a plane through it facing `direction`, with the
/// x axis Plane from Face would give (`FacePlane`: world X projected onto the plane, else world Y). It moves graphs
/// built on Grid Points over to Place without redrawing them. Points and directions broadcast: the longer list sets
/// the number of placements and the shorter repeats its last item.
public enum PointsToPlacementsNode: NodeDefinition {
    public static let typeID = "creator.pointsToPlacements"
    public static let displayName = "Points to Placements"
    public static let category = NodeCategory.patterns
    public static let inputs = [
        SocketSpec("points", .vector, access: .list),
        SocketSpec("direction", .vector, access: .list, defaultValue: .vector(.unitZ)),
    ]
    public static let outputs = [SocketSpec("placements", .plane)]
    public static let inspector = [InspectorSection(title: "Facing", controls: [.vector("direction")])]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let points = try inputs.vectors("points")
        let directions = try inputs.vectors("direction")
        let count = points.isEmpty || directions.isEmpty ? 0 : max(points.count, directions.count)
        try PatternLimit.check(count)
        var planes: [Scalar] = []
        planes.reserveCapacity(count)
        for index in 0..<count {
            guard let normal = directions[min(index, directions.count - 1)].normalized else {
                throw NodeError.invalidValue("The direction of placement \(InstancePath.text(index)) can't be zero.")
            }
            planes.append(.plane(FacePlane.plane(origin: points[min(index, points.count - 1)], normal: normal)))
        }
        return NodeOutputs(lists: ["placements": planes])
    }
}
