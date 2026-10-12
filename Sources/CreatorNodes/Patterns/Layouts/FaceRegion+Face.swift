import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation

extension FaceRegion {
    static let unreadable = "Face Pattern can't read this face's outline: it has an edge that is neither straight nor circular."

    /// The outline of the flat face `face` of `topology`, in 2D coordinates on the plane through `origin` spanned by the unit
    /// vectors `xAxis` and `yAxis`. Its boundary edges (seams aside) are joined into loops (`EdgeChains`); a face whose edges are
    /// not all straight or circular, or do not close up, can't be read and refuses.
    static func outline(of face: FaceInfo, in topology: Topology, origin: Vector3, xAxis: Vector3, yAxis: Vector3) throws -> FaceRegion {
        let edges = topology.edges.filter { !$0.isSeam && $0.faces.contains(face.id) }
        let curves = edges.compactMap(\.curve)
        guard !edges.isEmpty, curves.count == edges.count else { throw NodeError.invalidValue(unreadable) }
        let chains = EdgeChains.chains(of: curves)
        guard chains.allSatisfy(\.isClosed) else { throw NodeError.invalidValue(unreadable) }
        let loops = chains.map { chain in
            chain.pieces.flatMap { polyline(of: $0) }.map { point in
                Vector2((point - origin).dot(xAxis), (point - origin).dot(yAxis))
            }
        }
        return FaceRegion(loops: loops)
    }

    /// The points that stand for `piece`, from its start up to but not including its end: just the start for a line, chords for an arc.
    private static func polyline(of piece: EdgeCurve) -> [Vector3] {
        guard case .circle(_, _, let radius, _, let sweep) = piece, radius > 0 else { return [piece.startPoint] }
        let step = chordTolerance < radius ? 2 * acos(1 - chordTolerance / radius) : .pi
        let chords = min(max(Int((abs(sweep) / step).rounded(.up)), 1), 720)
        return (0..<chords).compactMap { piece.sample(at: piece.pathLength * Double($0) / Double(chords))?.point }
    }
}
