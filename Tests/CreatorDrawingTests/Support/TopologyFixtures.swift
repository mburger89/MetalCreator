import CreatorGeometry
import CreatorKernel

/// Hand-built topologies for the anchor resolver: faces named by one node, line and circle edges with exact curves.
enum TopologyFixtures {
    static let node = NodeID()
    static let other = NodeID()
    static let third = NodeID()

    static func tags(_ role: TopoRole, of owner: NodeID = node) -> Set<TopoTag> {
        [TopoTag(node: owner, item: 0, role: role)]
    }

    static func plane(_ id: Int, _ role: TopoRole, of owner: NodeID = node) -> FaceInfo {
        FaceInfo(
            id: FaceID(id), kind: .plane, normal: Vector3(0, 0, 1), area: 1, centroid: Vector3(0, 0, 0), tags: tags(role, of: owner))
    }

    static func cylinder(
        _ id: Int, _ role: TopoRole, axisPoint: Vector3 = Vector3(0, 0, 0), axis: Vector3 = Vector3(1, 0, 0), radius: Double = 5,
        of owner: NodeID = node
    ) -> FaceInfo {
        FaceInfo(
            id: FaceID(id), kind: .cylinder, normal: axis, area: 1, centroid: axisPoint, tags: tags(role, of: owner), radius: radius,
            axisPoint: axisPoint)
    }

    static func line(_ id: Int, _ start: Vector3, _ end: Vector3, between a: Int, _ b: Int) -> EdgeInfo {
        EdgeInfo(
            id: EdgeID(id), kind: .line, direction: (end - start).normalized, length: (end - start).length,
            midpoint: (start + end) * 0.5, convexity: .convex, faces: [FaceID(a), FaceID(b)], curve: .line(start: start, end: end))
    }

    static func circle(
        _ id: Int, center: Vector3, axis: Vector3, radius: Double, sweep: Double = 2 * .pi, between a: Int, _ b: Int
    ) -> EdgeInfo {
        let reference = abs(axis.z) > 0.9 ? Vector3(1, 0, 0) : Vector3(0, 0, 1)
        let start = center + (axis.cross(reference).normalized ?? Vector3(1, 0, 0)) * radius
        return EdgeInfo(
            id: EdgeID(id), kind: .circle, direction: axis, length: radius * sweep, midpoint: center, convexity: .convex,
            faces: [FaceID(a), FaceID(b)], curve: .circle(center: center, axis: axis, radius: radius, start: start, sweep: sweep))
    }

    /// A plate with four named faces (0 start cap, 1 end cap, 2 and 3 sides) and the given edges.
    static func plate(edges: [EdgeInfo], extraFaces: [FaceInfo] = []) -> Topology {
        let faces = [plane(0, .startCap), plane(1, .endCap), plane(2, .side(segment: 0)), plane(3, .side(segment: 1))]
        return Topology(faces: faces + extraFaces, edges: edges)
    }

    /// The pick that selects every edge `ids` of `topology` (their key), as a person's click records it.
    static func pick(_ topology: Topology, _ ids: [Int]) -> EdgePick {
        let edges = ids.compactMap { topology.edge(EdgeID($0)) }
        let key = topology.key(of: edges[0])!
        let matches = topology.edges(matching: key)
        let runs = Topology.runCount(matches)
        return EdgePick(key: key, matchCount: matches.count, runCount: runs == matches.count ? nil : runs)
    }
}
