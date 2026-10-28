import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation

/// The dimensions Fillet and Chamfer declare on the first edge of their set (spec §3.1).
enum EdgeDimensions {
    /// The first edge's midpoint, tangent, the two faces' normals and in-face directions, and the outward bisector.
    struct Corner {
        var midpoint: Vector3
        var normals: (Vector3, Vector3)
        var inFace: (Vector3, Vector3)
        var bisector: Vector3
        /// The interior angle between the faces, in radians.
        var interior: Double
    }

    /// `nil` for no edge, a seam edge (one face twice), a face without a normal, a flat or knife edge, or a bisector that vanishes.
    static func corner(of set: EdgeSet) -> Corner? {
        let topology = set.solid.topology
        guard let edge = set.edges.first.flatMap(topology.edge), edge.faces.count == 2, edge.faces[0] != edge.faces[1],
              let tangent = edge.direction?.normalized, edge.midpoint.isFinite,
              let first = topology.face(edge.faces[0]), let second = topology.face(edge.faces[1]),
              let n1 = first.normal?.normalized, let n2 = second.normal?.normalized,
              let bisector = (n1 + n2).normalized,
              let w1 = inFace(first.centroid - edge.midpoint, tangent), let w2 = inFace(second.centroid - edge.midpoint, tangent)
        else { return nil }
        let between = acos(max(-1, min(1, n1.dot(n2))))
        let interior = Double.pi - between
        guard between > 1e-6, sin(interior / 2) > 1e-6 else { return nil }
        return Corner(midpoint: edge.midpoint, normals: (n1, n2), inFace: (w1, w2), bisector: bisector, interior: interior)
    }

    /// Fillet radius: the arc's centre sits `r / sin(θ/2)` inside the edge along the bisector.
    static func fillet(_ set: EdgeSet, radius: Double) -> [DimensionSpec] {
        guard radius.isFinite, radius > 0, let corner = corner(of: set) else { return [] }
        let centre = corner.midpoint - corner.bisector * (radius / sin(corner.interior / 2))
        let geometry = DimensionGeometry.radial(center: centre, radius: radius, normal: tangent(of: set) ?? .unitZ,
                                                toward: corner.bisector, placement: .standoff)
        return [DimensionSpec(.input("radius"), geometry, .radius, value: radius, count: count(of: set))]
    }

    /// Chamfer distance: from the edge midpoint along the first face, away from the edge.
    static func chamfer(_ set: EdgeSet, distance: Double) -> [DimensionSpec] {
        guard distance.isFinite, distance > 0, let corner = corner(of: set) else { return [] }
        let w = corner.inFace.0
        let geometry = DimensionGeometry.linear(from: corner.midpoint, to: corner.midpoint + w * distance, direction: w,
                                                side: corner.normals.0, placement: .standoff)
        return [DimensionSpec(.input("distance"), geometry, .length, value: distance, count: count(of: set))]
    }

    private static func count(of set: EdgeSet) -> Int? { set.edges.count >= 2 ? set.edges.count : nil }

    private static func tangent(of set: EdgeSet) -> Vector3? {
        set.edges.first.flatMap(set.solid.topology.edge)?.direction?.normalized
    }

    /// The unit component of `vector` at right angles to `tangent`.
    private static func inFace(_ vector: Vector3, _ tangent: Vector3) -> Vector3? {
        (vector - tangent * vector.dot(tangent)).normalized
    }
}
