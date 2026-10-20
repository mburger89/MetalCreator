import CreatorKernel
import Foundation

/// Quadric error decimation (Garland and Heckbert; implicit spec §4.5): edge collapses in order of cost, from a priority queue. A
/// collapse is refused when it would make a vertex or an edge non-manifold (the link condition), flip a face, or cost more than the
/// tolerance. The cost is the quadric error at the new vertex, a sum of squared distances to the planes of every triangle the vertex
/// has absorbed, so its square root bounds the distance from the new vertex to each of those planes and the surface never moves
/// further than `tolerance` from where it was (a flat patch of k triangles costs √k times its noise, so the bound is a little
/// conservative on noisy flat areas). Vertices on an open edge are pinned: a mesh that is only a piece of a surface (one window of a
/// streamed export) keeps its edge exactly, and the piece beside it fits. A closed mesh stops at a tetrahedron.
public enum MeshDecimator {
    public struct Output: Sendable {
        public var positions: [SIMD3<Float>]
        public var triangles: [UInt32]
        /// For each output vertex, the input vertex it stands for. A vertex that never moved keeps its exact position.
        public var origin: [Int32]
        public var collapses: Int
    }

    public enum Failure: Error, Equatable, Sendable {
        /// An edge has more than two faces.
        case nonManifold(edges: Int)

        public var userMessage: String {
            switch self {
            case .nonManifold(let edges):
                "The mesh has \(edges.formatted(.number.locale(.messages))) edges with more than two faces, so it can't be simplified."
            }
        }
    }

    /// - Parameters:
    ///   - tolerance: the most a collapse may move the surface, in the mesh's units; 0 collapses only what is exactly flat.
    /// - Throws: `Failure.nonManifold` and `CancellationError`.
    public static func decimate(positions: [SIMD3<Float>], triangles: [UInt32], tolerance: Double) throws -> Output {
        var state = try MeshDecimationState(positions: positions, triangles: triangles)
        try state.run(tolerance: max(tolerance, 0))
        return state.output()
    }
}
