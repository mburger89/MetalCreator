import COCCT
import CreatorGeometry
import CreatorKernel

/// Faces and edges exactly as the shim reports them, before tags are applied.
/// Array index n corresponds to OCCT map index n + 1.
struct OCCTRawTopology: Sendable {
    struct Face: Sendable {
        var kind: SurfaceKind
        var normal: Vector3?
        var area: Double
        var centroid: Vector3
    }

    struct Edge: Sendable {
        var kind: CurveKind
        var direction: Vector3?
        var length: Double
        var midpoint: Vector3
        var convexity: Convexity
        /// 0-based face indices: two distinct for a normal edge, the same twice for a seam,
        /// none for a free edge.
        var faces: [Int]
    }

    var faces: [Face]
    var edges: [Edge]

    static func read(_ shape: OCCTShape) throws(OCCTError) -> OCCTRawTopology {
        var raw = occt_topology()
        defer { occt_topology_free(&raw) }
        try OCCTShape.check { status in occt_read_topology(shape.raw, &raw, status) }
        let faces = UnsafeBufferPointer(start: raw.faces, count: Int(raw.face_count)).map { info in
            Face(kind: surfaceKind(info.kind), normal: info.has_normal != 0 ? vector(info.normal) : nil,
                 area: info.area, centroid: vector(info.centroid))
        }
        let edges = UnsafeBufferPointer(start: raw.edges, count: Int(raw.edge_count)).map { info in
            Edge(kind: curveKind(info.kind), direction: info.has_direction != 0 ? vector(info.direction) : nil,
                 length: info.length, midpoint: vector(info.midpoint), convexity: convexity(info.convexity),
                 faces: info.face_a > 0 && info.face_b > 0 ? [Int(info.face_a) - 1, Int(info.face_b) - 1] : [])
        }
        return OCCTRawTopology(faces: faces, edges: edges)
    }

    static func vector(_ value: (Double, Double, Double)) -> Vector3 {
        Vector3(value.0, value.1, value.2)
    }

    private static func surfaceKind(_ code: Int32) -> SurfaceKind {
        switch code {
        case 0: .plane
        case 1: .cylinder
        case 2: .cone
        case 3: .sphere
        case 4: .torus
        case 5: .bspline
        default: .other
        }
    }

    private static func curveKind(_ code: Int32) -> CurveKind {
        switch code {
        case 0: .line
        case 1: .circle
        case 2: .ellipse
        case 3: .bspline
        default: .other
        }
    }

    private static func convexity(_ code: Int32) -> Convexity {
        switch code {
        case 0: .convex
        case 1: .concave
        case 2: .smooth
        default: .unknown
        }
    }
}
