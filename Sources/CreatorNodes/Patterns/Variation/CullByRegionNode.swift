import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Keeps or culls placements by where they are (patterns spec §4): inside or outside a profile, or within or beyond a distance
/// from a point, from an edge set, or from a face. A placement is judged by its origin. A profile is a prism along its plane's
/// normal, so a placement's height above the plane doesn't matter; a distance is taken to the point, to the nearest straight or
/// circular edge, or to the plane of the nearest flat face (a placement beside a small face counts as near it all the same).
/// A placement exactly on the outline or at exactly the distance counts as inside or within. Culling keeps paths: the rest keep
/// the indices they had, so a pick on one follows it (§6).
public enum CullByRegionNode: NodeDefinition {
    public static let typeID = "creator.cullByRegion"
    public static let displayName = "Cull by Region"
    public static let category = NodeCategory.patterns
    public static let references = ["Profile", "Point", "Edges", "Face"]
    public static let sides = ["Inside or within", "Outside or beyond"]
    public static let inputs = [
        SocketSpec("placements", .plane, access: .tree),
        SocketSpec("reference", .integer, defaultValue: .integer(0)),
        SocketSpec("keep", .integer, defaultValue: .integer(0)),
        SocketSpec("profile", .profile, optional: true),
        SocketSpec("point", .vector, optional: true),
        SocketSpec("edges", .edgeSet, optional: true),
        SocketSpec("faces", .faceSet, optional: true),
        SocketSpec("distance", .number, defaultValue: .number(10), unit: .millimetres, range: 0...1000),
    ]
    public static let outputs = [SocketSpec("placements", .plane)]
    public static let inspector = [
        InspectorSection(title: "Region", controls: [.segmented("reference", options: references), .slider("distance")]),
        InspectorSection(title: "Keep", controls: [.segmented("keep", options: sides)]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let tree = try inputs.tree("placements")
        guard tree.items.allSatisfy({ $0.type == .plane }) else { throw NodeError.typeMismatch("placements", expected: .plane) }
        let reference = try inputs.choice("reference", options: references)
        let keepsInside = try inputs.choice("keep", options: sides) == 0
        let distance = try inputs.number("distance")
        guard distance.isFinite, distance >= 0 else { throw NodeError.invalidValue("“distance” can't be negative.") }
        let isInside: @Sendable (Vector3) -> Bool
        switch reference {
        case 0:
            let profile = try inputs.profile("profile")
            isInside = { point in profile.contains(Self.local(point, in: profile.plane)) }
        case 1:
            let center = try inputs.vector("point")
            isInside = { ($0 - center).length <= distance + 1e-9 }
        case 2:
            let nearest = try RegionDistance.nearestEdge(try inputs.edgeSet("edges"))
            isInside = { nearest($0) <= distance + 1e-9 }
        default:
            guard case .faceSet(let faces) = try inputs.scalar("faces") else { throw NodeError.typeMismatch("faces", expected: .faceSet) }
            let nearest = try RegionDistance.nearestFace(faces)
            isInside = { nearest($0) <= distance + 1e-9 }
        }
        let kept = tree.keepingItems { leaf, _, k in
            guard case .plane(let plane) = leaf.items[k] else { return true }
            return isInside(plane.origin) == keepsInside
        }
        return NodeOutputs(trees: ["placements": kept])
    }

    /// `point` in the plane's own coordinates (the height above it dropped).
    private static func local(_ point: Vector3, in plane: Plane) -> Vector2 {
        let offset = point - plane.origin
        return Vector2(offset.dot(plane.xAxis), offset.dot(plane.yAxis))
    }
}
