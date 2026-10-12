import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Points in, placements out (patterns spec §3): each point becomes a plane through it facing `direction`, with the
/// x axis Plane from Face would give (`FacePlane`: world X projected onto the plane, else world Y). It moves graphs
/// built on Grid Points over to Place without redrawing them. Points and directions are read whole and matched as
/// `InstanceGrid` matches placements (the longer flat list sets the number of placements and the shorter repeats its last
/// item; a tree of points gives a tree of placements), and the placements come back in the shape of the points with the
/// same paths, so a cull anywhere before this node (on the points, say) keeps the paths of the instances that stay: a
/// culled list of points is a culled list of placements at the same indices.
public enum PointsToPlacementsNode: NodeDefinition {
    public static let typeID = "creator.pointsToPlacements"
    public static let displayName = "Points to Placements"
    public static let category = NodeCategory.patterns
    public static let inputs = [
        SocketSpec("points", .vector, access: .tree),
        SocketSpec("direction", .vector, access: .tree, defaultValue: .vector(.unitZ)),
    ]
    public static let outputs = [SocketSpec("placements", .plane)]
    public static let inspector = [InspectorSection(title: "Facing", controls: [.vector("direction")])]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let grid = try InstanceGrid(inputs, ["points", "direction"])
        guard grid.count > 0 else { return NodeOutputs(trees: ["placements": grid.tree(of: [])]) }
        let (points, directions) = (try grid.vectors("points"), try grid.vectors("direction"))
        var planes: [Scalar] = []
        planes.reserveCapacity(grid.count)
        for index in 0..<grid.count {
            guard let normal = directions[index].normalized else {
                throw NodeError.invalidValue("The direction of placement \(InstancePath.text(grid.items[index])) can't be zero.")
            }
            planes.append(.plane(FacePlane.plane(origin: points[index], normal: normal)))
        }
        return NodeOutputs(trees: ["placements": grid.tree(of: planes)])
    }
}
