import CreatorGeometry
import CreatorKernel

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// What the annotation tools work on: a plate extruded by `FakeKernel` with its Front and Top views, and a hand-built part
/// with a through hole, seen from the top (a face-on circle) and from the front (the hole's cylinder side on).
enum AnnotationEditorFixtures {
    static let centre = Vector2(150, 150)
    static let options = ProjectionOptions(tolerance: 0.01)

    // MARK: A plate made by the fake kernel

    /// A 40 x 20 plate 10 thick: the Front view is 40 by 10, the Top view 40 by 20.
    static func plate(_ orientation: StandardOrientation) async throws -> ViewContent {
        let kernel = FakeKernel()
        let solid = try await kernel.extrude(
            .rectangle(width: 40, height: 20, plane: .xy), distance: 10, mode: .oneSided, tag: NodeTag(node: NodeID(), item: 0))
        let projection = try await kernel.projection(of: solid, curves: [], frame: orientation.frame, options: options)
        return ViewContent(projection: projection, topology: solid.topology)
    }

    // MARK: A part with a hole

    private static let up = Vector3(0, 0, 1)
    private static let holeCentre = Vector3(20, 10, 0)

    private static func v(_ x: Double, _ y: Double, _ z: Double) -> Vector3 { Vector3(x, y, z) }
    private static func tags(_ role: TopoRole) -> Set<TopoTag> { [TopoTag(node: node, item: 0, role: role)] }
    private static let node = NodeID()

    private static func face(_ id: Int, _ kind: SurfaceKind, normal: Vector3, z: Double, radius: Double? = nil) -> FaceInfo {
        FaceInfo(
            id: FaceID(id), kind: kind, normal: normal, area: 1, centroid: v(20, 10, z), tags: tags(.side(segment: id)),
            radius: radius, axisPoint: radius == nil ? nil : holeCentre)
    }

    private static func line(_ id: Int, _ a: Vector3, _ b: Vector3, _ f: Int, _ g: Int) -> EdgeInfo {
        EdgeInfo(
            id: EdgeID(id), kind: .line, direction: (b - a).normalized, length: (b - a).length, midpoint: (a + b) * 0.5,
            convexity: .convex, faces: [FaceID(f), FaceID(g)], curve: .line(start: a, end: b))
    }

    private static func ring(_ id: Int, z: Double, _ f: Int, _ g: Int) -> EdgeInfo {
        let centre = v(20, 10, z)
        return EdgeInfo(
            id: EdgeID(id), kind: .circle, direction: up, length: 2 * .pi * 3, midpoint: centre, convexity: .convex,
            faces: [FaceID(f), FaceID(g)],
            curve: .circle(center: centre, axis: up, radius: 3, start: centre + Vector3(3, 0, 0), sweep: 2 * .pi))
    }

    /// Edges 102 (horizontal, `width` long), 100, 103 and 106 (verticals at x = 20, 40 and 30), 105 (diagonal), 104 (along the
    /// Top view's direction) and 101, with a through hole's rings 0 and 1 and its cylinder, face 2.
    static func topology(width: Double = 40, removing: [Int] = []) -> Topology {
        let faces = [
            face(0, .plane, normal: up, z: 0), face(1, .plane, normal: Vector3(0, 0, -1), z: -20),
            face(9, .plane, normal: Vector3(1, 0, 0), z: -10), face(8, .plane, normal: Vector3(0, -1, 0), z: -10),
            face(7, .plane, normal: Vector3(1, 0, 0), z: -10), face(6, .plane, normal: Vector3(1, -1, 0), z: -10),
            face(5, .plane, normal: Vector3(1, 0, 0), z: -10), face(2, .cylinder, normal: up, z: -10, radius: 3),
        ]
        let edges = [
            line(102, v(0, 0, 0), v(width, 0, 0), 0, 8), line(100, v(20, 0, 0), v(20, 20, 0), 0, 9),
            line(103, v(40, 0, 0), v(40, 20, 0), 0, 7), line(106, v(30, 0, 0), v(30, 20, 0), 0, 5),
            line(105, v(0, 0, 0), v(15, 15, 0), 0, 6), line(104, v(5, 5, 0), v(5, 5, -20), 8, 9),
            line(101, v(20, 0, -20), v(20, 20, -20), 1, 9), ring(0, z: 0, 2, 0), ring(1, z: -20, 2, 1),
        ]
        return Topology(faces: faces, edges: edges.filter { !removing.contains($0.id.rawValue) })
    }

    private static func projected(_ curve: ProjectedCurve, _ source: ProjectionSource?) -> ProjectedLine {
        ProjectedLine(visibility: .visible, lineClass: .sharp, curve: curve, source: source)
    }

    /// The part from the top: the lines of the edges above and the hole's ring, 3 mm in radius at (20, 10).
    static func top(_ topology: Topology = topology(), width: Double = 40) -> ViewContent {
        let lines = [
            projected(.line(Vector2(0, 0), Vector2(width, 0)), .edge(EdgeID(102))),
            projected(.line(Vector2(20, 0), Vector2(20, 20)), .edge(EdgeID(100))),
            projected(.line(Vector2(40, 0), Vector2(40, 20)), .edge(EdgeID(103))),
            projected(.line(Vector2(30, 0), Vector2(30, 20)), .edge(EdgeID(106))),
            projected(.line(Vector2(0, 0), Vector2(15, 15)), .edge(EdgeID(105))),
            projected(.arc(center: Vector2(20, 10), radius: 3, start: 0, sweep: 2 * .pi), .edge(EdgeID(0))),
        ]
        return ViewContent(projection: Projection2D(lines: lines), topology: topology)
    }

    /// The same part from the front: the hole's cylinder side on (two outlines at x = 17 and 23), the diagonal's depth running
    /// along the view direction and a bottom line, which is square to the view.
    static func front(_ topology: Topology = topology()) -> ViewContent {
        let lines = [
            projected(.line(Vector2(17, -20), Vector2(17, 0)), .face(FaceID(2))),
            projected(.line(Vector2(23, -20), Vector2(23, 0)), .face(FaceID(2))),
            projected(.line(Vector2(0, 0), Vector2(15, 0)), .edge(EdgeID(105))),
            projected(.line(Vector2(0, 10), Vector2(40, 10)), .edge(EdgeID(102))),
        ]
        return ViewContent(projection: Projection2D(lines: lines), topology: topology)
    }

    /// The pick that names edge `id` of `topology`, as a click records it.
    static func pick(_ topology: Topology, _ id: Int) -> AnchorTarget {
        let edge = topology.edge(EdgeID(id))!
        let key = topology.key(of: edge)!
        let matches = topology.edges(matching: key)
        return .edge(EdgePick(key: key, matchCount: matches.count, runCount: matches.count > 1 ? 1 : nil))
    }

    /// The view's mapping on the sheet at 1 : 1 about `centre`, as the composer makes it.
    static func mapping(_ content: ViewContent, at centre: Vector2 = AnnotationEditorFixtures.centre) -> ViewMapping {
        ViewMapping.of(projection: content.projection!, center: centre, scale: 1)!
    }
}
