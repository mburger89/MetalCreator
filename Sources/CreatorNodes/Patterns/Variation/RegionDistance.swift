import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation

/// How far a point is from the things Cull by Region measures from (patterns spec §4): a point, the edges of an edge set, or
/// the flat faces of a face set. Straight and circular edges are measured exactly; a curved face is not measured at all.
enum RegionDistance {
    /// The distance from `point` to the nearest of `edges`, which must all be straight or circular.
    static func nearestEdge(_ edges: EdgeSet) throws -> @Sendable (Vector3) -> Double {
        let found = edges.edges.compactMap { edges.solid.topology.edge($0) }
        guard !found.isEmpty else { throw NodeError.invalidValue("“edges” is empty, so there is nothing to measure from.") }
        let curves = found.compactMap(\.curve)
        guard curves.count == found.count else {
            let other = found.count - curves.count
            throw NodeError.invalidValue("Cull by Region measures from straight and circular edges: \(other.display) of the "
                + "\(found.count.display) selected \(found.count == 1 ? "edge is" : "edges are") another kind of curve.")
        }
        return { point in curves.map { distance(from: point, to: $0) }.min() ?? .infinity }
    }

    /// The distance from `point` to the nearest of the flat faces of `faces`, taken to the face's plane.
    static func nearestFace(_ faces: FaceSet) throws -> @Sendable (Vector3) -> Double {
        let found = faces.faces.compactMap { faces.solid.topology.face($0) }
        guard !found.isEmpty else { throw NodeError.invalidValue("“faces” is empty, so there is nothing to measure from.") }
        let planes = found.compactMap { face -> (origin: Vector3, normal: Vector3)? in
            guard face.kind == .plane, let normal = face.normal?.normalized else { return nil }
            return (face.centroid, normal)
        }
        guard planes.count == found.count else {
            throw NodeError.invalidValue("Cull by Region measures from flat faces for now: \((found.count - planes.count).display) of the "
                + "\(found.count.display) selected \(found.count == 1 ? "face is" : "faces are") curved.")
        }
        return { point in planes.map { abs(($0.normal).dot(point - $0.origin)) }.min() ?? .infinity }
    }

    /// The distance from `point` to `curve` (the maths lives on `EdgeCurve`, shared with the Fake kernel).
    static func distance(from point: Vector3, to curve: EdgeCurve) -> Double {
        curve.distance(from: point)
    }
}
